import AppKit
import Combine
import NoFormatNotesCore
import SwiftUI

/// The menu bar icon and everything you can do to it.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because MenuBarExtra swallows the click and
/// gives no way to see which modifier keys were held. Telling a plain click from a modified one is
/// the whole point here: the fastest path to an empty note is one click, no panel, no second click.
///
/// The modifier is Option, not Command. macOS reserves Command-drag on menu bar items for
/// rearranging them, so a Command-click with the left button is consumed by the system and never
/// reaches the app at all. Option is unreserved, and is the established convention for an alternate
/// action on a menu bar item, which is what the Wi-Fi, Volume and Bluetooth menus use it for.
@MainActor
final class StatusItemController: NSObject {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: NotesModel
    private let updates: UpdateChecker
    private let openNote: (Note) -> Void
    private var updateObserver: AnyCancellable?
    private var currentSymbol = "note.text"

    init(model: NotesModel, updates: UpdateChecker, openNote: @escaping (Note) -> Void) {
        self.model = model
        self.updates = updates
        self.openNote = openNote
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NoFormatNotes")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(clicked)
            // Both buttons, so right-click can be handled too.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "NoFormatNotes\nClick for notes\nOption-click or right-click for a new note"
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: MenuContent(model: model, updates: updates, openNote: { [weak self] note in
                self?.popover.performClose(nil)
                openNote(note)
            })
        )

        // The daily check is silent, so without a badge a new version would only ever be seen by
        // someone who happened to open the panel and look.
        updateObserver = updates.$state.sink { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem.button else { return }
                let wanted: String
                if case .available = state { wanted = "note.text.badge.plus" } else { wanted = "note.text" }
                // Only touch the image when the symbol actually changes. Assigning it re-renders and
                // snapshots the status item layer, which is cheap once and ruinous if something ever
                // starts publishing frequently.
                guard wanted != self.currentSymbol else { return }
                self.currentSymbol = wanted
                button.image = NSImage(systemSymbolName: wanted, accessibilityDescription: "NoFormatNotes")
                button.image?.isTemplate = true
            }
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []

        // Option-click, or a right-click, goes straight to a new note. No panel, no second click.
        //
        // Command is deliberately not used: macOS consumes Command-click on a menu bar item for its
        // own rearrange gesture, so the action never fires. Command with the right button does get
        // through, so that is accepted too rather than silently doing nothing.
        let wantsNewNote = modifiers.contains(.option)
            || event?.type == .rightMouseUp
        if wantsNewNote {
            popover.performClose(nil)
            openNote(model.newNote())
            return
        }

        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Refresh from disk in case a note was changed elsewhere.
            model.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
