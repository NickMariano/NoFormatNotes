import Foundation

/// Reduces text to what a plain text editor can represent, and nothing else.
///
/// The point is that what you see is exactly what is stored. Pasting from a browser, a document or a
/// chat window otherwise drags in characters that look ordinary and are not: smart quotes, non
/// breaking spaces, zero width joiners. In prose they are invisible. In an API key or a command they
/// are the reason something fails with an error that makes no sense.
public enum PlainText {

    /// Characters that look like ASCII but are not, mapped to what they appear to be.
    private static let lookalikes: [Character: Character] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'",  // single quotes
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"",  // double quotes
        "\u{2013}": "-", "\u{2014}": "-", "\u{2015}": "-", "\u{2212}": "-",  // dashes and minus
        "\u{00A0}": " ", "\u{2007}": " ", "\u{202F}": " ", "\u{205F}": " ",  // non breaking spaces
        "\u{2002}": " ", "\u{2003}": " ", "\u{2009}": " ", "\u{3000}": " ",  // typographic spaces
        "\u{2044}": "/", "\u{2215}": "/",                                      // fraction slashes
    ]

    /// Invisible characters with no business in plain text. Removed outright rather than replaced,
    /// since there is nothing they could sensibly become.
    private static let invisible: Set<Character> = [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}",  // zero width space, joiners, word joiner
        "\u{FEFF}",                                       // byte order mark
        "\u{00AD}",                                       // soft hyphen
        "\u{200E}", "\u{200F}",                           // directional marks
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",  // directional overrides
    ]

    /// Cleans text for storage and display.
    ///
    /// Line endings are normalised to `\n`, tabs and newlines are kept, every other control
    /// character is dropped, lookalikes become their ASCII equivalent, and invisible characters are
    /// removed. Nothing else is altered: content is never trimmed, wrapped or reflowed, because a
    /// key or a token has to come back out exactly as it went in.
    public static func clean(_ input: String) -> String {
        // Precomposed form, so text that looks identical is stored identically. macOS hands out
        // decomposed strings in places, and two visually identical notes should not differ in bytes.
        var text = input.precomposedStringWithCanonicalMapping
        // Normalise line endings, so \r\n does not survive as a stray \r.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        var result = String()
        result.reserveCapacity(text.count)

        for character in text {
            if invisible.contains(character) { continue }
            if let replacement = lookalikes[character] {
                result.append(replacement)
                continue
            }
            // Keep tab and newline; drop every other control character, including the NUL and
            // escape sequences a terminal copy can carry.
            if let scalar = character.unicodeScalars.first,
               character.unicodeScalars.count == 1,
               scalar.properties.generalCategory == .control,
               character != "\n", character != "\t" {
                continue
            }
            result.append(character)
        }

        return result
    }

    /// Characters from other scripts that are visually identical to ASCII.
    ///
    /// These are never removed automatically. Doing so would mangle legitimate Russian, Greek or
    /// fullwidth text, and this is a notes app, not an ASCII enforcer. But in a key or a token they
    /// are indistinguishable from the character they imitate and break it with no visible cause, so
    /// the app points them out and offers to convert them.
    private static let homoglyphs: [Character: Character] = [
        // Cyrillic
        "\u{0430}": "a", "\u{0435}": "e", "\u{043E}": "o", "\u{0440}": "p", "\u{0441}": "c",
        "\u{0445}": "x", "\u{0443}": "y", "\u{0456}": "i", "\u{0458}": "j", "\u{04BB}": "h",
        "\u{0410}": "A", "\u{0412}": "B", "\u{0415}": "E", "\u{041A}": "K", "\u{041C}": "M",
        "\u{041D}": "H", "\u{041E}": "O", "\u{0420}": "P", "\u{0421}": "C", "\u{0422}": "T",
        "\u{0425}": "X", "\u{0405}": "S",
        // Greek
        "\u{03BF}": "o", "\u{03B1}": "a", "\u{03B5}": "e", "\u{03C1}": "p", "\u{03BD}": "v",
        "\u{0391}": "A", "\u{0392}": "B", "\u{0395}": "E", "\u{0396}": "Z", "\u{0397}": "H",
        "\u{0399}": "I", "\u{039A}": "K", "\u{039C}": "M", "\u{039D}": "N", "\u{039F}": "O",
        "\u{03A1}": "P", "\u{03A4}": "T", "\u{03A7}": "X",
    ]

    /// A character that imitates ASCII, and what it appears to be.
    public struct Lookalike: Sendable, Hashable {
        public let character: Character
        public let looksLike: Character
        public let codePoint: String
    }

    /// Finds characters that imitate ASCII, judged in context.
    ///
    /// Context is the whole point. A Cyrillic "а" inside "заметка" is simply a Russian word, and
    /// converting it would vandalise the note. The same character inside "sk-proj-аBc123" is a
    /// corrupted key. So a run of text is only examined when it is mostly ASCII already: the
    /// lookalike is the odd one out rather than the norm.
    public static func lookalikes(in input: String) -> [Lookalike] {
        var found: [Lookalike] = []
        var seen = Set<Character>()

        for token in input.split(whereSeparator: { $0.isWhitespace }) {
            let characters = Array(token)
            let asciiCount = characters.filter { $0.isASCII }.count
            // Mostly ASCII, and long enough for the judgement to mean anything. Below this the
            // signal is too weak and every stray character would be flagged.
            guard characters.count >= 3,
                  Double(asciiCount) / Double(characters.count) >= 0.5 else { continue }

            for character in characters where !seen.contains(character) {
                guard let ascii = asciiEquivalent(of: character) else { continue }
                seen.insert(character)
                let point = character.unicodeScalars
                    .map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                found.append(Lookalike(character: character, looksLike: ascii, codePoint: point))
            }
        }
        return found
    }

    /// The ASCII character this one imitates, if it imitates one.
    private static func asciiEquivalent(of character: Character) -> Character? {
        if let mapped = homoglyphs[character] { return mapped }
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return nil
        }
        // Fullwidth forms: a direct offset from their ASCII counterparts.
        if scalar.value >= 0xFF01 && scalar.value <= 0xFF5E,
           let ascii = Unicode.Scalar(scalar.value - 0xFEE0) {
            return Character(ascii)
        }
        // Mathematical alphanumerics, the styled letters that paste out of rich documents.
        if scalar.value >= 0x1D400 && scalar.value <= 0x1D7FF {
            let normalized = String(character).folding(options: .diacriticInsensitive, locale: nil)
                .applyingTransform(.toLatin, reverse: false) ?? ""
            if let first = normalized.first, first.isASCII { return first }
        }
        return nil
    }

    /// Converts ASCII-imitating characters, but only inside the runs that were flagged.
    ///
    /// Applying this everywhere would turn "заметка" into "зaмeткa": visually identical, entirely
    /// wrong. Only mostly-ASCII runs are touched, matching exactly what `lookalikes(in:)` reported.
    public static func foldLookalikes(_ input: String) -> String {
        var result = String()
        result.reserveCapacity(input.count)
        var token = String()

        func flushToken() {
            guard !token.isEmpty else { return }
            let characters = Array(token)
            let asciiCount = characters.filter { $0.isASCII }.count
            let eligible = characters.count >= 3 && Double(asciiCount) / Double(characters.count) >= 0.5
            result += eligible ? String(characters.map { asciiEquivalent(of: $0) ?? $0 }) : token
            token.removeAll(keepingCapacity: true)
        }

        for character in input {
            if character.isWhitespace {
                flushToken()
                result.append(character)
            } else {
                token.append(character)
            }
        }
        flushToken()
        return result
    }

    /// True when cleaning would change the text, so the UI can say something was stripped.
    public static func needsCleaning(_ input: String) -> Bool {
        clean(input) != input
    }

    /// The first non-empty line, used as a note's title in lists.
    public static func title(of body: String, fallback: String = "New Note") -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(60))
            }
        }
        return fallback
    }
}
