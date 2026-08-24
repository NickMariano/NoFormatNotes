import Foundation

public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var body: String
    public var modified: Date

    public var title: String { PlainText.title(of: body) }

    public init(id: UUID = UUID(), body: String = "", modified: Date = Date()) {
        self.id = id
        self.body = body
        self.modified = modified
    }
}

/// Notes on disk, as ordinary `.txt` files in one folder.
///
/// Plain files rather than a database so the notes remain readable, greppable and recoverable with
/// nothing but Finder, and so a bug here can never make them unreadable.
///
/// The location is `~/Library/Application Support`, deliberately not Documents or Desktop: those are
/// swept into iCloud when Desktop & Documents syncing is on, and anything pasted here is expected to
/// stay on this machine.
public final class NoteStore: @unchecked Sendable {

    public let directory: URL
    private let queue = DispatchQueue(label: "com.stealthpyro.NoFormatNotes.store")

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NoFormatNotes", isDirectory: true)
        prepareDirectory()
    }

    /// Creates the folder if needed, owner-only, and asks Spotlight not to index it.
    ///
    /// These notes are expected to hold things like API keys. Owner-only permissions keep them out
    /// of reach of other accounts on the machine, and the index exclusion keeps their contents from
    /// being surfaced by a Spotlight search or by anything that queries the index.
    private func prepareDirectory() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        }
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let marker = directory.appendingPathComponent(".metadata_never_index")
        if !manager.fileExists(atPath: marker.path) {
            manager.createFile(atPath: marker.path, contents: Data())
        }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).txt")
    }

    // MARK: - Reading

    /// All notes, newest first.
    public func load() -> [Note] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var notes: [Note] = []
        for file in entries where file.pathExtension == "txt" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let body = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            notes.append(Note(id: id, body: body, modified: modified))
        }
        return notes.sorted { $0.modified > $1.modified }
    }

    // MARK: - Writing

    /// Writes a note, owner-readable only.
    ///
    /// Writes to a temporary file and replaces the original, so an interrupted write cannot leave a
    /// half-written note where a whole one used to be.
    public func save(_ note: Note) {
        queue.sync {
            let destination = url(for: note.id)
            let temporary = destination.appendingPathExtension("writing")
            let data = Data(note.body.utf8)

            let manager = FileManager.default
            guard manager.createFile(atPath: temporary.path, contents: data,
                                     attributes: [.posixPermissions: 0o600]) else { return }
            _ = try? manager.replaceItemAt(destination, withItemAt: temporary)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }

    public func delete(_ note: Note) {
        queue.sync {
            try? FileManager.default.removeItem(at: url(for: note.id))
        }
    }

    /// Overwrites a note's bytes before deleting it.
    ///
    /// Not a secure erase in the forensic sense, which is not achievable on a modern SSD from user
    /// space, but it does stop the contents being trivially recoverable from an undeleted file.
    public func shred(_ note: Note) {
        queue.sync {
            let target = url(for: note.id)
            if let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size]) as? Int,
               size > 0 {
                let noise = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                try? noise.write(to: target)
            }
            try? FileManager.default.removeItem(at: target)
        }
    }
}
