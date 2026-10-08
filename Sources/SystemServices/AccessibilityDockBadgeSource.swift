import AppKit
import ApplicationServices

/// Reads badges from Apple's Dock through Accessibility, where each app's tile carries its
/// badge as the `AXStatusLabel` attribute. This is the long-standing way to read other apps'
/// badges (there's no public API), and unlike Launch Services' per-app `StatusLabel`, it also
/// sees the badges system apps such as Messages get from the notification system.
///
/// It needs Accessibility access, and a tile for the app in Apple's Dock. Every running app
/// has one there (as do apps kept in it), and hiding Apple's Dock with auto-hide, as
/// `AppleDockHider` does, doesn't remove them.
@MainActor
public final class AccessibilityDockBadgeSource: DockBadgeSource {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let accessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    public init() {}

    public func hasAccess(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        // The value of `kAXTrustedCheckOptionPrompt`, a mutable global strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessSettings() {
        guard let url = Self.accessSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    public func readBadges() async throws -> [DockBadge] {
        guard
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleIdentifier).first
        else { throw DockBadgeReadError.dockNotRunning }
        let pid = dock.processIdentifier
        return try await Task.detached(priority: .utility) {
            try DockTiles.badges(inDockProcess: pid)
        }.value
    }
}

/// Every call here is a synchronous round trip to Apple's Dock, so reads run off the main
/// thread, with a short timeout so a busy Dock can't hold them up for long.
private enum DockTiles {
    static let messagingTimeout: Float = 0.5

    enum Attribute {
        static let children = "AXChildren"
        static let subrole = "AXSubrole"
        static let title = "AXTitle"
        static let url = "AXURL"
        static let statusLabel = "AXStatusLabel"
    }

    /// The badges on the tiles of the Dock's lists (it has one, holding every tile).
    static func badges(inDockProcess pid: pid_t) throws(DockBadgeReadError) -> [DockBadge] {
        let dock = AXUIElementCreateApplication(pid)
        var badges: [DockBadge] = []
        for list in try children(of: dock) {
            // A list that goes away mid-read (the Dock restarting) is skipped.
            for tile in (try? children(of: list)) ?? [] {
                if let badge = badge(on: tile) { badges.append(badge) }
            }
        }
        return badges
    }

    private static func children(of element: AXUIElement) throws(DockBadgeReadError) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, Attribute.children as CFString, &value) {
        case .success: return value as? [AXUIElement] ?? []
        case .noValue, .attributeUnsupported: return []
        case .apiDisabled: throw .accessDenied
        default: throw .failed
        }
    }

    /// One round trip per tile for everything needed, rather than one per attribute.
    private static func badge(on tile: AXUIElement) -> DockBadge? {
        AXUIElementSetMessagingTimeout(tile, messagingTimeout)
        let attributes = [Attribute.subrole, Attribute.statusLabel, Attribute.url, Attribute.title]
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(tile, attributes as CFArray, [], &values) == .success,
            let values = values as? [AnyObject], values.count == attributes.count
        else { return nil }
        // Missing attributes come back as error values, which these casts turn into nil.
        let url = values[2] as? URL
        guard
            var badge = DockBadge(
                subrole: values[0] as? String, statusLabel: values[1] as? String, url: url,
                title: values[3] as? String)
        else { return nil }
        badge.bundleIdentifier = url.flatMap { Bundle(url: $0)?.bundleIdentifier }
        return badge
    }
}
