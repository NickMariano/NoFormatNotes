import Foundation
import NoFormatNotesCore
import SwiftUI

/// The notes the UI binds to, and the owner of when they get written.
@MainActor
final class NotesModel: ObservableObject {

    @Published private(set) var notes: [Note] = []

    private let store = NoteStore()
    /// Notes edited but not yet written, keyed by id.
    private var pending: [UUID: Note] = [:]
    private var flushTimer: Timer?

    /// How long after the last keystroke a note is written.
    ///
    /// Short enough that nothing is lost in practice, long enough that typing does not cause a disk
    /// write per character. Quitting, closing a window and losing focus all flush immediately, so
    /// this delay is never the difference between saved and not.
    private let autosaveDelay: TimeInterval = 0.4

    var directory: URL { store.directory }

    init() {
        notes = store.load()

        // Anything unwritten goes to disk before the process ends, however it ends.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: - Editing

    @discardableResult
    func newNote() -> Note {
        let note = Note()
        notes.insert(note, at: 0)
        // Written straight away, so an empty note still exists if the app dies before any typing.
        store.save(note)
        return note
    }

    func note(id: UUID) -> Note? {
        pending[id] ?? notes.first { $0.id == id }
    }

    /// Records an edit and schedules a write.
    func update(id: UUID, body: String) {
        // Cleaning on the way in means what is stored is exactly what is shown, and a paste from a
        // browser cannot smuggle in characters that look like ASCII and are not.
        let cleaned = PlainText.clean(body)
        guard var note = note(id: id) else { return }
        guard note.body != cleaned else { return }

        note.body = cleaned
        note.modified = Date()
        pending[id] = note

        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index] = note
        }

        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: autosaveDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Writes everything outstanding.
    func flush() {
        flushTimer?.invalidate()
        flushTimer = nil
        guard !pending.isEmpty else { return }
        for note in pending.values {
            store.save(note)
        }
        pending.removeAll()
    }

    // MARK: - Deleting

    func delete(id: UUID) {
        guard let note = note(id: id) else { return }
        pending.removeValue(forKey: id)
        // Overwritten before removal: these notes are expected to hold things worth not leaving
        // lying around in a deleted file.
        store.shred(note)
        notes.removeAll { $0.id == id }
    }

    func reload() {
        flush()
        notes = store.load()
    }

    /// Notes sorted for display, most recently edited first.
    var sorted: [Note] {
        notes.sorted { $0.modified > $1.modified }
    }
}
