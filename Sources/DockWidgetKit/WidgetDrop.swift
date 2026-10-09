import AppKit
import Foundation

/// What a drag over the dock carries, for widgets that take drops (see
/// `DockWidget.acceptsDrop(_:instance:)`): the URLs on its pasteboard, files and links
/// alike, and its plain text, in pasteboard order.
public struct WidgetDrop: Equatable, Sendable {
    public var urls: [URL]
    public var texts: [String]

    public init(urls: [URL] = [], texts: [String] = []) {
        self.urls = urls
        self.texts = texts
    }

    /// Reads a drag's pasteboard.
    public init(pasteboard: NSPasteboard) {
        urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        texts = pasteboard.readObjects(forClasses: [NSString.self]) as? [String] ?? []
    }

    public var fileURLs: [URL] { urls.filter(\.isFileURL) }

    public var isEmpty: Bool { urls.isEmpty && texts.isEmpty }
}
