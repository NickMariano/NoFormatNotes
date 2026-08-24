import AppKit
import NoFormatNotesCore

// The laundering workflow: copy from a web page or email, paste into a plain editor, copy back out,
// and paste somewhere else with no styling attached.
//
// Two halves have to hold. Pasting in must discard styling, and copying back out must offer only
// plain text on the pasteboard. The second is the one that matters: if the editor still writes RTF
// when you copy, the receiving app takes the RTF and the styling comes back.

@MainActor
func main() {
    let pasteboard = NSPasteboard.general

    // Preserve the user's clipboard and put it back at the end.
    let saved: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
        var copy: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types { copy[type] = item.data(forType: type) }
        return copy
    } ?? []

    /// A text view configured exactly as the app's editor is.
    func makeEditor() -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isRichText = false
        view.importsGraphics = false
        view.allowsImageEditing = false
        return view
    }

    func trial(_ label: String, build: () -> Void) {
        pasteboard.clearContents()
        build()
        let offered = pasteboard.types?.map(\.rawValue) ?? []

        // Half one: paste in.
        let editor = makeEditor()
        editor.string = ""
        _ = editor.readSelection(from: pasteboard)
        let landed = PlainText.clean(editor.string)

        // Half two: select all and copy back out.
        editor.string = landed
        editor.setSelectedRange(NSRange(location: 0, length: (landed as NSString).length))
        pasteboard.clearContents()
        _ = editor.writeSelection(to: pasteboard, type: .string)
        editor.copy(nil)
        let writtenBack = pasteboard.types?.map(\.rawValue) ?? []

        print("  \(label)")
        print("    clipboard had:      \(offered.joined(separator: ", "))")
        print("    editor received:    \(landed.debugDescription)")
        print("    copying out gives:  \(writtenBack.joined(separator: ", "))")
        let styled = writtenBack.filter { $0.contains("rtf") || $0.contains("html") || $0.contains("rtfd") }
        print("    styled types out:   \(styled.isEmpty ? "NONE - plain text only" : styled.joined(separator: ", "))")
        print("")
    }

    print("--- laundering rich content ---\n")

    trial("Rich text: bold, 24pt, red, highlighted, with a link") {
        let rich = NSMutableAttributedString(string: "Bold red highlighted text and a link\n")
        rich.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.red,
            .backgroundColor: NSColor.yellow,
        ], range: NSRange(location: 0, length: 25))
        rich.addAttributes([
            .link: URL(string: "https://example.com")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: NSRange(location: 31, length: 4))
        if let data = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
            pasteboard.setData(data, forType: .rtf)
        }
        pasteboard.setString("Bold red highlighted text and a link\n", forType: .string)
    }

    trial("HTML from a web page, with a smart quote and nbsp") {
        let html = """
        <html><body><h1 style="color:blue;font-size:32px">Heading</h1>\
        <p style="background:#ff0"><b>bold</b> <i>italic</i>&nbsp;\u{201C}quoted\u{201D}</p></body></html>
        """
        pasteboard.setData(Data(html.utf8), forType: .html)
        pasteboard.setString("Heading\nbold italic\u{00A0}\u{201C}quoted\u{201D}", forType: .string)
    }

    trial("An API key carrying a zero-width space") {
        pasteboard.setString("\u{201C}zk-proj-abc\u{200B}def\u{201D}", forType: .string)
    }

    // Restore.
    pasteboard.clearContents()
    for entry in saved {
        let item = NSPasteboardItem()
        for (type, data) in entry { item.setData(data, forType: type) }
        pasteboard.writeObjects([item])
    }
    print("  (your clipboard has been restored)")
}

main()
