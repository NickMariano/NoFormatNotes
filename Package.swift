// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoFormatNotes",
    platforms: [.macOS(.v15)],
    targets: [
        // Storage and text handling, free of any UI, so both can be tested without a running app.
        .target(name: "NoFormatNotesCore"),
        .executableTarget(name: "NoFormatNotesApp", dependencies: ["NoFormatNotesCore"]),
        // Tests run as a plain executable: no XCTest or swift-testing in Command Line Tools.
        .executableTarget(name: "NoFormatNotesTests", dependencies: ["NoFormatNotesCore"]),
        // Shows exactly what the cleaner does to a range of inputs.
        .executableTarget(name: "NoFormatNotesProbe", dependencies: ["NoFormatNotesCore"]),
        .executableTarget(name: "NoFormatNotesPasteProbe", dependencies: ["NoFormatNotesCore"]),
    ]
)
