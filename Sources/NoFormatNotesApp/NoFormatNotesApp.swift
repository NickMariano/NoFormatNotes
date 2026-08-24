import AppKit
import NoFormatNotesCore
import SwiftUI

/// A menu bar app: no Dock icon, no main window, just the icon and whatever notes are open.
@main
struct NoFormatNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item is built in the delegate, since it needs click handling SwiftUI's
        // MenuBarExtra does not expose. This scene exists only to satisfy the App protocol.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NotesModel?
    private var statusItem: StatusItemController?
    private var windows: NoteWindowController?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { start() }
    }

    private func start() {
        // If this relaunches from /Applications, the process exits here and the copy takes over.
        if MoveToApplications.offerIfNeeded() { return }

        let model = NotesModel()
        let windows = NoteWindowController(model: model)
        self.model = model
        self.windows = windows
        statusItem = StatusItemController(model: model, openNote: { note in
            windows.open(note)
        })
    }

    /// Anything unwritten goes to disk before the process ends.
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.flush() }
    }
}
