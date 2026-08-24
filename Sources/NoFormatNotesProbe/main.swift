import Foundation
import NoFormatNotesCore

func render(_ s: String) -> String {
    s.unicodeScalars.map { u -> String in
        if u.value < 32 { return "\\u{\(String(u.value, radix: 16))}" }
        if u.value > 126 { return "\(u)[U+\(String(format: "%04X", u.value))]" }
        return String(u)
    }.joined()
}

func show(_ label: String, _ input: String) {
    let out = PlainText.clean(input)
    print("  \(out != input ? "CHANGED " : "kept    ")  \(label)")
    if out != input { print("            \(render(input))  ->  \(render(out))") }
}

print("--- cleaned automatically ---")
// Swift compares strings by canonical equivalence, so a precomposed and decomposed form are ==
// even though the bytes differ. Compare scalar counts to see the normalisation actually happen.
let nfd = "e\u{0301}"
let nfc = PlainText.clean(nfd)
print("  \(nfd.unicodeScalars.count == nfc.unicodeScalars.count ? "kept    " : "CHANGED ")  NFD to NFC: \(nfd.unicodeScalars.count) scalars -> \(nfc.unicodeScalars.count) scalars")

for (l, s) in [("smart quotes", "\u{201C}x\u{201D}"), ("em dash", "a\u{2014}b"),
               ("non-breaking space", "a\u{00A0}b"), ("zero-width space", "zk-abc\u{200B}def"),
               ("BOM", "\u{FEFF}key"), ("NUL byte", "a\u{0000}b"), ("CRLF", "a\r\nb")]
                { show(l, s) }

print("\n--- kept, correctly ---")
for (l, s) in [("ascii key", "zk-proj-AbC_123"), ("emoji", "note 🔑"),
               ("accented", "café"), ("CJK", "日本語")] { show(l, s) }

print("\n--- flagged as ASCII lookalikes, not silently changed ---")
for (label, sample) in [
    ("Cyrillic a", "sk-\u{0430}bc"),
    ("Greek omicron", "t\u{03BF}ken"),
    ("fullwidth a", "\u{FF41}bc"),
    ("mathematical bold A", "\u{1D400}BC"),
    ("mixed real key", "zk-proj-\u{0430}Bc\u{03BF}123"),
    ("legitimate Russian", "заметка"),
    ("clean ascii key", "zk-proj-aBc123"),
] {
    let found = PlainText.lookalikes(in: sample)
    if found.isEmpty {
        print("  none      \(label)")
    } else {
        let detail = found.map { "\($0.character) (\($0.codePoint)) looks like '\($0.looksLike)'" }
        print("  \(found.count) found  \(label): \(detail.joined(separator: ", "))")
        print("            fix -> \(PlainText.foldLookalikes(sample))")
    }
}
