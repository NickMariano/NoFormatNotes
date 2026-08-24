import AppKit

/// Offers to move the app into /Applications on first launch.
///
/// This matters more than it looks. The app is distributed as a disk image, so the obvious mistake
/// is to run it straight from the mounted image: the login item would then point at a path that
/// disappears on eject, and every note would be written by an app that vanishes.
enum MoveToApplications {

    static let destination = "/Applications/NoFormatNotes.app"
    static var currentPath: String { Bundle.main.bundlePath }
    static var isInApplications: Bool { currentPath == destination }

    static var isOnReadOnlyVolume: Bool {
        (try? URL(fileURLWithPath: currentPath)
            .resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    /// Returns true when this process is standing down, in which case the caller must stop.
    @discardableResult
    static func offerIfNeeded() -> Bool {
        guard !isInApplications else { return false }

        // Already installed and this is a stray copy: hand over rather than asking anything.
        if FileManager.default.fileExists(atPath: destination) {
            launchInstalledCopy()
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Move NoFormatNotes to Applications?"
        alert.informativeText = isOnReadOnlyVolume
            ? "NoFormatNotes is running from the disk image. Move it to Applications so it stays available after you eject."
            : "NoFormatNotes works best from your Applications folder, so it stays available and can open at login."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try FileManager.default.copyItem(atPath: currentPath, toPath: destination)
            // Clear quarantine on the copy so the relaunch does not trip Gatekeeper again.
            let strip = Process()
            strip.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            strip.arguments = ["-dr", "com.apple.quarantine", destination]
            try? strip.run()
            strip.waitUntilExit()

            if !isOnReadOnlyVolume { try? FileManager.default.removeItem(atPath: currentPath) }
            launchInstalledCopy()
            return true
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not move NoFormatNotes"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag it to Applications yourself, then open it from there."
            failure.runModal()
            return false
        }
    }

    /// Detached and delayed, so this process is gone before the replacement starts and cannot be
    /// mistaken by it for an already-running instance.
    private static func launchInstalledCopy() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open -a '\(destination)'"]
        try? process.run()
        exit(0)
    }
}
