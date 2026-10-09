import Foundation

/// What a drop on the AirDrop tile would send: the files and web links among the things
/// dragged, in the order they were dragged, each once. AirDrop sends files and links and
/// nothing else, so text that isn't a link, and URLs with other schemes (`mailto:`,
/// `data:`), are left out.
public struct AirDropPayload: Equatable, Sendable {
    /// Files and folders, as `file:` URLs, standardized.
    public private(set) var files: [URL] = []
    /// `http` and `https` links.
    public private(set) var links: [URL] = []

    public init() {}

    /// Sorts `urls` into files and links. Each of `texts` is taken as a link when the whole
    /// of it, trimmed, is one; that's how a selected address, or a link from a browser's
    /// address bar, arrives when it has no URL of its own.
    public init(urls: [URL], texts: [String] = []) {
        for url in urls { add(url) }
        for text in texts {
            if let link = Self.link(in: text) { add(link) }
        }
    }

    public var isEmpty: Bool { files.isEmpty && links.isEmpty }

    public var count: Int { files.count + links.count }

    /// Everything to send, files first, for `NSSharingService`.
    public var items: [URL] { files + links }

    /// Adds `url` to the files or the links, or ignores it when AirDrop can't send it, or
    /// it's already here. Files are compared by `normalizedPath`, links by their text.
    public mutating func add(_ url: URL) {
        if url.isFileURL {
            let path = url.normalizedPath
            guard path.count > 1, !files.contains(where: { $0.normalizedPath == path }) else { return }
            files.append(url.standardizedFileURL)
        } else if Self.isLink(url) {
            guard !links.contains(where: { $0.absoluteString == url.absoluteString }) else { return }
            links.append(url)
        }
    }

    /// Whether `url` is a web link: `http` or `https`, with a host.
    public static func isLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return url.host(percentEncoded: false)?.isEmpty == false
    }

    /// The link `text` is, if its whole content (trimmed) is one web address.
    public static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed), isLink(url)
        else { return nil }
        return url
    }

    /// What the payload holds, in words: "3 files", "1 link", "2 files and 1 link".
    public var summary: String {
        let parts = [
            Self.counted(files.count, "file", "files"),
            Self.counted(links.count, "link", "links"),
        ].compactMap { $0 }
        return parts.isEmpty ? "Nothing to send" : parts.joined(separator: " and ")
    }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String? {
        switch count {
        case 0: return nil
        case 1: return "1 \(singular)"
        default: return "\(count) \(plural)"
        }
    }
}
