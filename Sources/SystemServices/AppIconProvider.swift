import AppKit

/// Loads and caches file-system icons at the sizes the dock needs.
/// `NSWorkspace.icon(forFile:)` is cheap but not free; the cache keeps hover and
/// resize smooth.
@MainActor
public final class AppIconProvider {
    public static let shared = AppIconProvider()

    private var cache: [URL: NSImage] = [:]

    private init() {}

    public func icon(for url: URL) -> NSImage {
        let key = url.standardizedFileURL
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key.path)
        // Ask for the largest representation so Retina rendering stays crisp
        // regardless of the slider value.
        image.size = NSSize(width: 256, height: 256)
        cache[key] = image
        return image
    }

    public func invalidate(_ url: URL) {
        cache.removeValue(forKey: url.standardizedFileURL)
    }

    public func invalidateAll() {
        cache.removeAll()
    }
}
