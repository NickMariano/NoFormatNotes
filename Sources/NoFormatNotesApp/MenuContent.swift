import AppKit
import NoFormatNotesCore
import SwiftUI

/// The menu bar panel: the list of notes, and the one click that makes a new one.
struct MenuContent: View {
    @ObservedObject var model: NotesModel
    @ObservedObject var updates: UpdateChecker
    var openNote: (Note) -> Void

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            noteList
            Divider()
            footer
        }
        .frame(width: 300)
    }

    private var header: some View {
        Button {
            openNote(model.newNote())
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .keyboardShortcut("n")
        .help("Create a note and start typing")
    }

    @ViewBuilder
    private var noteList: some View {
        if model.notes.isEmpty {
            Text("No notes yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.sorted) { note in
                        NoteRow(note: note,
                                open: { openNote(note) },
                                delete: { model.delete(id: note.id) })
                        if note.id != model.sorted.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            // Explicit height: a ScrollView in a self-sizing menu bar window has no intrinsic
            // height and collapses to nothing.
            .frame(height: min(CGFloat(model.notes.count) * 42, 320))
        }
    }

    @ViewBuilder
    private var updateItems: some View {
        switch updates.state {
        case .checking:   Text("Checking for updates...")
        case .installing: Text("Installing update...")
        case let .available(version):
            Button("Install Update \(version)...") { updates.installUpdate() }
            Button("What's New in \(version)") { updates.openReleasePage() }
        case .upToDate:
            Text("Version \(updates.currentVersion) is up to date")
            Button("Check Again") { updates.check(userInitiated: true) }
        case let .failed(message):
            Text("Update check failed: \(message)")
            Button("Try Again") { updates.check(userInitiated: true) }
        case .idle:
            Button("Check for Updates...") { updates.check(userInitiated: true) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { wanted in
                    do {
                        try LoginItem.setEnabled(wanted)
                        launchAtLogin = LoginItem.isEnabled
                        loginError = LoginItem.isBlockedByUser
                            ? "Allow NoFormatNotes under System Settings > General > Login Items."
                            : nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = LoginItem.isEnabled
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)

            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case let .available(version) = updates.state {
                Button { updates.installUpdate() } label: {
                    Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            Text("Tip: Option-click or right-click the icon for an instant new note.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.directory.path)
                }
                .controlSize(.small)
                Spacer()
                // Quit stays a plain button. Burying the way out of an app inside a menu is worse
                // than showing it, and this panel has room.
                Menu {
                    updateItems
                    Divider()
                    Button("Uninstall NoFormatNotes...") { Uninstaller.run(model: model) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More options")

                Button("Quit") {
                    model.flush()
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct NoteRow: View {
    let note: Note
    var open: () -> Void
    var delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .lineLimit(1)
                    .font(.callout)
                Text(note.modified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            // Delete appears on hover: one click to remove, but not sitting there to be hit by
            // accident while reaching for a note.
            if hovering {
                Button(action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete this note")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 42)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
    }
}
