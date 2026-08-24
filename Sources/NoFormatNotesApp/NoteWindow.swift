import AppKit
import NoFormatNotesCore
import SwiftUI

private extension NSWindow {
    /// Front-to-back position, used only to cascade a new window off the most recent one.
    var orderedIndex: Int { NSApp.windows.firstIndex(of: self) ?? Int.max }
}

/// One window per note, kept open until closed.
@MainActor
final class NoteWindowController {

    private var windows: [UUID: NSWindow] = [:]
    private let model: NotesModel

    init(model: NotesModel) { self.model = model }

    func open(_ note: Note) {
        if let existing = windows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = NoteView(
            noteID: note.id,
            model: model,
            onDelete: { [weak self] in self?.close(note.id) },
            onTitleChange: { [weak self] title in self?.retitle(note.id, to: title) }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = note.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        // Cascade, so a second note does not land exactly on top of the first.
        if let previous = windows.values.max(by: { $0.orderedIndex > $1.orderedIndex }) {
            window.setFrameTopLeftPoint(NSPoint(x: previous.frame.minX + 24,
                                                y: previous.frame.maxY - 24))
        }

        // Anything unwritten goes to disk the moment a window closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.flush()
                self?.windows.removeValue(forKey: note.id)
            }
        }

        windows[note.id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(_ id: UUID) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }

    func retitle(_ id: UUID, to title: String) {
        windows[id]?.title = title
    }
}

private struct NoteView: View {
    let noteID: UUID
    @ObservedObject var model: NotesModel
    var onDelete: () -> Void
    var onTitleChange: (String) -> Void

    @State private var text: String = ""
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            PlainTextEditor(text: $text) { updated in
                model.update(id: noteID, body: updated)
                // The window title follows the note's first line, so a stack of open notes is
                // distinguishable. Without this every window stays titled "New Note" forever.
                onTitleChange(PlainText.title(of: updated))
            }

            Divider()

            HStack {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .onAppear {
            text = model.note(id: noteID)?.body ?? ""
            onTitleChange(PlainText.title(of: text))
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.delete(id: noteID)
                onDelete()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var status: String {
        let characters = text.count
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(lines) line\(lines == 1 ? "" : "s"), \(characters) character\(characters == 1 ? "" : "s") - saved automatically"
    }
}
