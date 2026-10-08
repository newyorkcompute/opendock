import Foundation

/// User preferences for how the dock looks and behaves.
public struct DockSettings: Hashable, Codable, Sendable {
    public enum Edge: String, Codable, Sendable, CaseIterable {
        case bottom
        case left
        case right
    }

    public enum Material: String, Codable, Sendable, CaseIterable {
        /// Liquid Glass on macOS 26+, falls back to frosted on older systems.
        case glass
        case frosted
        case solid
    }

    /// Which screen edge the dock is attached to. MVP only implements `.bottom`.
    public var edge: Edge
    /// Which display the dock is on.
    public var display: Display
    /// Size in points of app icons. Widgets scale their height to match.
    public var iconSize: Double
    /// Hide the dock when the pointer leaves it; reveal by touching the screen edge.
    public var autoHide: Bool
    /// Seconds to wait after the pointer leaves before hiding.
    public var autoHideDelay: Double
    public var material: Material
    /// Show a small dot under running apps.
    public var showRunningIndicators: Bool
    /// Show apps that are running but not pinned, after a divider.
    public var showRunningApps: Bool
    /// Magnify items near the pointer, like the Dock's Magnification setting.
    /// (Persisted under its original name, from when it was a simple hover scale.)
    public var hoverEffect: Bool
    /// How large the item directly under the pointer grows, as a multiple of `iconSize`.
    public var magnification: Double
    /// Hide Apple's Dock while OpenDock runs; its settings are restored afterwards.
    public var hideAppleDock: Bool
    /// Global shortcuts that switch to the next and previous profile, wrapping around.
    public var nextProfileHotKey: HotKey?
    public var previousProfileHotKey: HotKey?
    /// Switch profiles by swiping sideways on the dock, or scrolling over it with ⌘ held.
    public var switchProfilesByScrolling: Bool
    /// Bounce an app's icon while the app launches, like the Dock's "Animate opening
    /// applications" setting.
    public var animateOpeningApps: Bool
    /// Clicking the frontmost app's icon minimizes its windows, and clicking it again
    /// restores them. Needs Accessibility access.
    public var clickToMinimize: Bool
    /// Show apps' badges (unread counts and the like) on their icons, read from Apple's Dock.
    public var showBadges: Bool
    /// Show the apps used most recently that aren't pinned or running, after the running
    /// apps and a divider, like the Dock's "Show suggested and recent apps" setting.
    public var showRecentApps: Bool
    /// How many recent apps to show at most.
    public var recentAppsCount: Int
    /// Show the dock over a full-screen app while the pointer is held at the screen edge,
    /// like Apple's Dock. Off, the dock never appears on full-screen Spaces.
    public var revealInFullScreen: Bool

    public init(
        edge: Edge = .bottom,
        display: Display = .main,
        iconSize: Double = 48,
        autoHide: Bool = false,
        autoHideDelay: Double = 0.4,
        material: Material = .glass,
        showRunningIndicators: Bool = true,
        showRunningApps: Bool = false,
        hoverEffect: Bool = true,
        magnification: Double = 1.5,
        hideAppleDock: Bool = false,
        nextProfileHotKey: HotKey? = nil,
        previousProfileHotKey: HotKey? = nil,
        switchProfilesByScrolling: Bool = true,
        animateOpeningApps: Bool = true,
        clickToMinimize: Bool = false,
        showBadges: Bool = true,
        showRecentApps: Bool = false,
        recentAppsCount: Int = 3,
        revealInFullScreen: Bool = true
    ) {
        self.edge = edge
        self.display = display
        self.iconSize = iconSize
        self.autoHide = autoHide
        self.autoHideDelay = autoHideDelay
        self.material = material
        self.showRunningIndicators = showRunningIndicators
        self.showRunningApps = showRunningApps
        self.hoverEffect = hoverEffect
        self.magnification = magnification
        self.hideAppleDock = hideAppleDock
        self.nextProfileHotKey = nextProfileHotKey
        self.previousProfileHotKey = previousProfileHotKey
        self.switchProfilesByScrolling = switchProfilesByScrolling
        self.animateOpeningApps = animateOpeningApps
        self.clickToMinimize = clickToMinimize
        self.showBadges = showBadges
        self.showRecentApps = showRecentApps
        self.recentAppsCount = recentAppsCount.clamped(to: Self.recentAppsCountRange)
        self.revealInFullScreen = revealInFullScreen
    }

    public static let `default` = DockSettings()

    public static let iconSizeRange: ClosedRange<Double> = 32 ... 96
    public static let magnificationRange: ClosedRange<Double> = 1.2 ... 2.0
    public static let recentAppsCountRange: ClosedRange<Int> = 1 ... 10

    /// Scale of the item under the pointer: 1 when magnification is off.
    public var peakMagnification: Double {
        hoverEffect ? magnification.clamped(to: Self.magnificationRange) : 1
    }
}

// MARK: - Tolerant decoding

extension DockSettings {
    /// Decode with defaults for any missing keys so adding a setting never
    /// invalidates an existing settings file.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DockSettings.default
        edge = try c.decodeIfPresent(Edge.self, forKey: .edge) ?? d.edge
        display = (try? c.decodeIfPresent(Display.self, forKey: .display)) ?? d.display
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? d.autoHide
        autoHideDelay = try c.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? d.autoHideDelay
        material = try c.decodeIfPresent(Material.self, forKey: .material) ?? d.material
        showRunningIndicators =
            try c.decodeIfPresent(Bool.self, forKey: .showRunningIndicators) ?? d.showRunningIndicators
        showRunningApps = try c.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? d.showRunningApps
        hoverEffect = try c.decodeIfPresent(Bool.self, forKey: .hoverEffect) ?? d.hoverEffect
        magnification = ((try? c.decodeIfPresent(Double.self, forKey: .magnification)) ?? d.magnification)
            .clamped(to: Self.magnificationRange)
        hideAppleDock = (try? c.decodeIfPresent(Bool.self, forKey: .hideAppleDock)) ?? d.hideAppleDock
        nextProfileHotKey = (try? c.decodeIfPresent(HotKey.self, forKey: .nextProfileHotKey)) ?? d.nextProfileHotKey
        previousProfileHotKey =
            (try? c.decodeIfPresent(HotKey.self, forKey: .previousProfileHotKey)) ?? d.previousProfileHotKey
        switchProfilesByScrolling =
            (try? c.decodeIfPresent(Bool.self, forKey: .switchProfilesByScrolling))
            ?? d.switchProfilesByScrolling
        animateOpeningApps = (try? c.decodeIfPresent(Bool.self, forKey: .animateOpeningApps)) ?? d.animateOpeningApps
        clickToMinimize = (try? c.decodeIfPresent(Bool.self, forKey: .clickToMinimize)) ?? d.clickToMinimize
        showBadges = (try? c.decodeIfPresent(Bool.self, forKey: .showBadges)) ?? d.showBadges
        showRecentApps = (try? c.decodeIfPresent(Bool.self, forKey: .showRecentApps)) ?? d.showRecentApps
        recentAppsCount = ((try? c.decodeIfPresent(Int.self, forKey: .recentAppsCount)) ?? d.recentAppsCount)
            .clamped(to: Self.recentAppsCountRange)
        revealInFullScreen = (try? c.decodeIfPresent(Bool.self, forKey: .revealInFullScreen)) ?? d.revealInFullScreen
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
