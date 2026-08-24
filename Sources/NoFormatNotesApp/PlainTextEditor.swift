import AppKit
import NoFormatNotesCore
import SwiftUI

/// A genuinely plain text editor.
///
/// SwiftUI's `TextEditor` is backed by a rich text view: it will happily accept styled text on
/// paste, and it applies substitutions like smart quotes and automatic dashes as you type. Both
/// defeat the point here, so this wraps `NSTextView` directly with every one of those behaviours
/// turned off, and cleans anything that arrives by paste or drag.
struct PlainTextEditor: NSViewRepresentable {

    @Binding var text: String
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesInspectorBar = false

        // Every "helpful" substitution, off. These are what turn a typed quote into a curly one and
        // a double hyphen into an em dash, which is exactly what must not happen to a key.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // Only touch the view when the value genuinely differs, or the caret jumps while typing.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: PlainTextEditor

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let raw = textView.string
            let cleaned = PlainText.clean(raw)

            // Rewrite in place only when something was actually stripped, preserving the caret.
            // Doing it unconditionally would fight the text system on every keystroke.
            if cleaned != raw {
                let caret = textView.selectedRange().location
                let removed = raw.utf16.count - cleaned.utf16.count
                textView.string = cleaned
                let adjusted = max(0, min(caret - removed, cleaned.utf16.count))
                textView.setSelectedRange(NSRange(location: adjusted, length: 0))
            }

            parent.text = cleaned
            parent.onChange(cleaned)
        }
    }
}
