import AppKit

/// Hands a note over to a full notes app, for the times a scratch note turns out to be worth
/// keeping.
///
/// Done with a URL scheme rather than a shared framework or a common folder: neither app needs to
/// know the other exists at build time, either can be installed without the other, and nothing here
/// breaks if the destination is never installed.
enum KeepHandoff {

    private static let scheme = "separateopinion"

    /// Whether anything on this machine can receive a handoff, so the button is only shown when it
    /// would actually do something.
    static var isAvailable: Bool {
        guard let url = URL(string: "\(scheme)://new") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    static func send(_ text: String, tag: String = "inbox") {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "tag", value: tag),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
