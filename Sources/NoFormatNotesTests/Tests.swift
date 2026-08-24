import Foundation
import NoFormatNotesCore

// MARK: - Text cleaning
//
// The rule that matters: an API key or token must survive exactly. Everything else is secondary.

private func apiKeysSurviveUntouched() {
    scope("Keys, tokens and paths pass through byte for byte")
    // Deliberately not real vendor prefixes. These exercise the character classes that matter
    // (mixed case, digits, underscores, hyphens, base64 padding, long runs), without embedding
    // strings that secret scanners flag as live credentials, which would be noise at best and a
    // blocked push at worst.
    let samples = [
        "zk-proj-AbC123_def-456GHI789jkl",
        "tokentype_16C7e42F292c6912E7710c838347Ae178B4a",
        "QKIAIOSFODNN7SAMPLE",
        "zoxb-123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx",
        "-----BEGIN KEY-----\nabc+/=\n-----END KEY-----",
        "/Users/someone/path/to file.txt",
        "{\"key\": \"value\", \"n\": 1.5}",
        "password with  double  spaces",
        "tab\tseparated\tvalues",
    ]
    for sample in samples {
        expect(PlainText.clean(sample) == sample, "changed: \(sample)")
    }
}

private func smartQuotesBecomePlain() {
    scope("Typographic characters become their ASCII equivalent")
    expect(PlainText.clean("\u{201C}quoted\u{201D}") == "\"quoted\"")
    expect(PlainText.clean("it\u{2019}s") == "it's")
    expect(PlainText.clean("a \u{2014} b") == "a - b")
    expect(PlainText.clean("a \u{2013} b") == "a - b")
}

private func invisiblesAreRemoved() {
    scope("Invisible characters are stripped, not left lurking")
    // The realistic failure: a key copied from a web page carries a zero width space and the API
    // rejects it, with nothing visible to explain why.
    expect(PlainText.clean("zk-abc\u{200B}def") == "zk-abcdef")
    expect(PlainText.clean("\u{FEFF}token") == "token")
    expect(PlainText.clean("a\u{00AD}b") == "ab")
    expect(PlainText.clean("x\u{202E}y") == "xy")
}

private func nonBreakingSpacesBecomeSpaces() {
    scope("Non-breaking spaces become ordinary spaces")
    expect(PlainText.clean("a\u{00A0}b") == "a b")
    expect(PlainText.clean("a\u{202F}b") == "a b")
}

private func lineEndingsNormalise() {
    scope("Line endings normalise to \\n")
    expect(PlainText.clean("a\r\nb") == "a\nb")
    expect(PlainText.clean("a\rb") == "a\nb")
    expect(PlainText.clean("a\nb") == "a\nb")
}

private func controlCharactersGo() {
    scope("Control characters are dropped, tabs and newlines kept")
    expect(PlainText.clean("a\u{0000}b") == "ab")
    expect(PlainText.clean("a\u{001B}[31mb") == "a[31mb")
    expect(PlainText.clean("keep\ttab\nand newline") == "keep\ttab\nand newline")
}

private func cleaningIsIdempotent() {
    scope("Cleaning twice changes nothing further")
    let messy = "\u{201C}a\u{200B}b\u{201D}\r\nc\u{00A0}d"
    let once = PlainText.clean(messy)
    expect(PlainText.clean(once) == once)
}

private func emptyAndWhitespace() {
    scope("Empty and whitespace-only input is preserved, not trimmed")
    expect(PlainText.clean("") == "")
    expect(PlainText.clean("   ") == "   ")
    expect(PlainText.clean("\n\n") == "\n\n")
}

private func titles() {
    scope("Title is the first non-empty line")
    expect(PlainText.title(of: "hello\nworld") == "hello")
    expect(PlainText.title(of: "\n\n  spaced  \nmore") == "spaced")
    expect(PlainText.title(of: "") == "New Note")
    expect(PlainText.title(of: "   ") == "New Note")
    expect(PlainText.title(of: String(repeating: "x", count: 100)).count == 60)
}

// MARK: - Storage

private func storageRoundTrip() {
    scope("A saved note comes back exactly")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoFormatNotesTest-\(UUID().uuidString)")
    let store = NoteStore(directory: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let body = "zk-proj-secret\nline two\twith tab"
    let note = Note(body: body)
    store.save(note)

    let loaded = store.load()
    expect(loaded.count == 1, "expected 1 note, got \(loaded.count)")
    expect(loaded.first?.body == body, "body changed on round trip")
    expect(loaded.first?.id == note.id, "id changed")
}

private func storagePermissions() {
    scope("Notes are readable only by their owner")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoFormatNotesTest-\(UUID().uuidString)")
    let store = NoteStore(directory: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let note = Note(body: "secret")
    store.save(note)

    let dirPerms = (try? FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions]) as? NSNumber
    expect(dirPerms?.int16Value == 0o700, "directory is \(String(dirPerms?.intValue ?? -1, radix: 8)), want 700")

    let file = directory.appendingPathComponent("\(note.id.uuidString).txt")
    let filePerms = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]) as? NSNumber
    expect(filePerms?.int16Value == 0o600, "file is \(String(filePerms?.intValue ?? -1, radix: 8)), want 600")
}

private func storageDeletes() {
    scope("Deleting removes the file and its contents")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoFormatNotesTest-\(UUID().uuidString)")
    let store = NoteStore(directory: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let note = Note(body: "sensitive value")
    store.save(note)
    store.shred(note)

    expect(store.load().isEmpty, "note still present after delete")
    let file = directory.appendingPathComponent("\(note.id.uuidString).txt")
    expect(!FileManager.default.fileExists(atPath: file.path), "file still on disk")
}

private func storageSurvivesRestart() {
    scope("Notes persist across a new store instance, as after a restart")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoFormatNotesTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = NoteStore(directory: directory)
    first.save(Note(body: "one"))
    first.save(Note(body: "two"))

    // A completely fresh store, as a relaunched app would build.
    let second = NoteStore(directory: directory)
    let loaded = second.load()
    expect(loaded.count == 2, "expected 2 notes after reload, got \(loaded.count)")
    expect(Set(loaded.map(\.body)) == ["one", "two"], "bodies did not survive")
}

private func storageIgnoresStrangeFiles() {
    scope("Unrelated files in the folder are ignored, not loaded as notes")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NoFormatNotesTest-\(UUID().uuidString)")
    let store = NoteStore(directory: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    store.save(Note(body: "real"))
    try? "not a note".write(to: directory.appendingPathComponent("random.txt"),
                            atomically: true, encoding: .utf8)
    try? "also not".write(to: directory.appendingPathComponent("notes.json"),
                          atomically: true, encoding: .utf8)

    let loaded = store.load()
    expect(loaded.count == 1, "expected 1 note, got \(loaded.count)")
    expect(loaded.first?.body == "real")
}

let allTests: [@Sendable () -> Void] = [
    apiKeysSurviveUntouched,
    smartQuotesBecomePlain,
    invisiblesAreRemoved,
    nonBreakingSpacesBecomeSpaces,
    lineEndingsNormalise,
    controlCharactersGo,
    cleaningIsIdempotent,
    emptyAndWhitespace,
    titles,
    storageRoundTrip,
    storagePermissions,
    storageDeletes,
    storageSurvivesRestart,
    storageIgnoresStrangeFiles,
]
