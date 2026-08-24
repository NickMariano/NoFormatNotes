import AppKit
import Foundation
import NoFormatNotesCore

/// Removes NoFormatNotes.
///
/// Dragging the app to the Trash leaves the login item registered and every note on disk. The notes
/// are the part that matters: they are expected to hold things like API keys, so removing the app
/// without dealing with them leaves those sitting in Application Support indefinitely.
@MainActor
enum Uninstaller {

    static let appPath = "/Applications/NoFormatNotes.app"

    static func run(model: NotesModel) {
        let noteCount = model.notes.count

        let alert = NSAlert()
        alert.messageText = "Uninstall NoFormatNotes?"
        alert.informativeText = noteCount == 0
            ? "This removes NoFormatNotes and its login item."
            : "This removes NoFormatNotes and its login item.\n\nYou have \(noteCount) note\(noteCount == 1 ? "" : "s"). Choose whether to keep or delete them."
        alert.addButton(withTitle: noteCount == 0 ? "Uninstall" : "Delete Notes Too")
        if noteCount > 0 { alert.addButton(withTitle: "Keep Notes") }
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let choice = alert.runModal()
        let cancel: NSApplication.ModalResponse = noteCount == 0 ? .alertSecondButtonReturn : .alertThirdButtonReturn
        guard choice != cancel else { return }

        if choice == .alertFirstButtonReturn {
            // Overwritten before removal, then the folder itself.
            for note in model.notes { model.delete(id: note.id) }
            try? FileManager.default.removeItem(at: model.directory)
        }

        try? LoginItem.setEnabled(false)

        // The app removes itself last, detached, so the shell outlives this process and can delete
        // the bundle it is running from.
        if FileManager.default.fileExists(atPath: appPath) {
            let script = "sleep 1; rm -rf '\(appPath)'"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            try? process.run()
        }

        NSApp.terminate(nil)
    }
}
