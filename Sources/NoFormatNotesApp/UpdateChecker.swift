import AppKit
import Foundation

/// Checks GitHub Releases for a newer version, and installs it in place.
///
/// The downloaded image is verified before anything is run from it: the app inside must be signed by
/// the same Developer Team as this build, and must pass Gatekeeper. Fetching an executable over the
/// network and running it is exactly where a substituted file does the most damage, so neither the
/// release metadata nor HTTPS is trusted on its own.
@MainActor
final class UpdateChecker: ObservableObject {

    static let repository = "NickMariano/NoFormatNotes"
    private static let lastCheckKey = "lastUpdateCheck"
    /// Once a day is plenty, and stays well inside GitHub's unauthenticated rate limit.
    private static let checkInterval: TimeInterval = 60 * 60 * 24

    struct Release {
        let version: String
        let downloadURL: URL
        let notesURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var latest: Release?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    var updateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    // MARK: - Checking

    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard last == nil || Date().timeIntervalSince(last!) > Self.checkInterval else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard state != .checking, state != .installing else { return }
        state = .checking

        Task {
            do {
                let release = try await fetchLatest()
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                latest = release
                state = Self.isNewer(release.version, than: currentVersion)
                    ? .available(version: release.version)
                    : .upToDate
            } catch {
                // A background check must not nag about a flaky network.
                state = userInitiated ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let notes = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError.malformed
        }
        guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString), url.scheme == "https" else {
            throw UpdateError.noPackage
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       downloadURL: url, notesURL: notes)
    }

    /// Numeric component-wise, so 1.10 is newer than 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    // MARK: - Installing

    func installUpdate() {
        guard let release = latest else { return }
        state = .installing

        Task {
            do {
                let image = try await download(release)
                let mounted = try mount(image)
                defer { unmount(mounted) }

                let newApp = mounted.appendingPathComponent("NoFormatNotes.app")
                try verify(newApp)
                try replaceSelf(with: newApp)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func download(_ release: Release) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoFormatNotes-\(release.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func mount(_ image: URL) throws -> URL {
        let point = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoFormatNotesUpdate-\(UUID().uuidString)")
        _ = try Self.run("/usr/bin/hdiutil",
                         ["attach", image.path, "-nobrowse", "-quiet", "-mountpoint", point.path])
        return point
    }

    private func unmount(_ point: URL) {
        _ = try? Self.run("/usr/bin/hdiutil", ["detach", point.path, "-quiet"])
    }

    /// Refuses anything not signed by this build's own team and accepted by Gatekeeper.
    private func verify(_ app: URL) throws {
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError.untrusted("the disk image does not contain the app")
        }
        let signature = try Self.run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path])
        guard let team = Self.teamIdentifier, signature.contains("TeamIdentifier=\(team)") else {
            throw UpdateError.untrusted("it is not signed by the same developer as this copy")
        }
        _ = try Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    /// Replaces the installed app and relaunches.
    ///
    /// A running app cannot reliably replace its own bundle, so the copy is staged and a detached
    /// shell does the swap after this process exits. Waiting on the pid rather than sleeping a fixed
    /// interval means the bundle is never replaced underneath a process still using it.
    private func replaceSelf(with newApp: URL) throws {
        let installed = Bundle.main.bundlePath
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoFormatNotes-staged-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: newApp, to: URL(fileURLWithPath: staging.path))

        guard FileManager.default.isWritableFile(atPath: (installed as NSString).deletingLastPathComponent) else {
            // Not writable, which happens for a non-admin account. Show the image and let them drag.
            NSWorkspace.shared.selectFile(newApp.path, inFileViewerRootedAtPath: newApp.deletingLastPathComponent().path)
            throw UpdateError.untrusted("cannot write to \((installed as NSString).deletingLastPathComponent). Drag the new copy across yourself.")
        }

        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(installed)'
        cp -R '\(staging.path)' '\(installed)'
        rm -rf '\(staging.path)'
        xattr -dr com.apple.quarantine '\(installed)' 2>/dev/null
        open '\(installed)'
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()

        NSApp.terminate(nil)
    }

    /// This build's Team ID, read from its own signature rather than hardcoded.
    static var teamIdentifier: String? {
        guard let output = try? run("/usr/bin/codesign", ["-dv", "--verbose=2", Bundle.main.bundlePath]) else {
            return nil
        }
        for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value == "not set" ? nil : value
        }
        return nil
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError.untrusted(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    func openReleasePage() {
        NSWorkspace.shared.open(latest?.notesURL
            ?? URL(string: "https://github.com/\(Self.repository)/releases/latest")!)
    }
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case malformed
    case noPackage
    case untrusted(String)

    var errorDescription: String? {
        switch self {
        case let .badResponse(code): return "GitHub returned \(code)."
        case .malformed: return "Could not read the release information."
        case .noPackage: return "That release has no disk image attached."
        case let .untrusted(detail): return "Refused the update: \(detail)"
        }
    }
}
