import DockCore
import SwiftUI

// Environment values the shell injects so widgets can adapt without knowing about it.

public extension EnvironmentValues {
    /// Height, in points, that dock items (and therefore widget tiles) should be. Inside a
    /// widget it includes the widget's magnification, so a tile sized from it is laid out
    /// again, with sharp text, at each magnified size.
    @Entry var dockIconSize: Double = 48

    /// How far the dock has magnified this widget, 1 at rest. Already part of
    /// `dockIconSize`; multiply sizes in fixed points by it.
    @Entry var dockWidgetScale: Double = 1

    /// The screen edge the dock is on. On a side edge the dock is a column an icon wide,
    /// and tiles stack their content rather than lining it up (see `WidgetTile`).
    @Entry var dockEdge: DockSettings.Edge = .bottom

    /// False while the dock is hidden off-screen. Widgets should pause expensive
    /// polling and animations when this is false.
    @Entry var dockIsVisible: Bool = true

    /// False while the welcome window is up on a fresh install. Widgets shouldn't ask for a
    /// permission on their own until it's true, so the system prompt doesn't compete with
    /// the welcome window. Asking because the user clicked something is still fine.
    @Entry var widgetsMayRequestAccess: Bool = true

    /// Call to persist changed settings for the current widget instance.
    @Entry var widgetUpdateSettings = WidgetSettingsUpdater.noop
}

/// Persists a widget instance's settings. Equatable by item ID so SwiftUI doesn't
/// invalidate every widget whenever the environment is rebuilt.
public struct WidgetSettingsUpdater: Equatable {
    public let id: UUID
    private let handler: @MainActor (WidgetInstance) -> Void

    public init(id: UUID, handler: @escaping @MainActor (WidgetInstance) -> Void) {
        self.id = id
        self.handler = handler
    }

    public static let noop = WidgetSettingsUpdater(id: UUID(uuid: UUID_NULL)) { _ in }

    public func callAsFunction(_ instance: WidgetInstance) {
        handler(instance)
    }

    /// Convenience: copy `instance`, set one key, persist.
    public func set(_ key: String, to value: String?, in instance: WidgetInstance) {
        var copy = instance
        copy.settings[key] = value
        handler(copy)
    }

    public static func == (lhs: WidgetSettingsUpdater, rhs: WidgetSettingsUpdater) -> Bool {
        lhs.id == rhs.id
    }
}

/// Standard sizing helpers so all widgets agree on proportions.
public enum WidgetMetrics {
    /// Corner radius for a tile at the given icon size.
    public static func cornerRadius(for iconSize: Double) -> Double {
        max(10, iconSize * 0.26)
    }

    /// Horizontal padding inside a tile.
    public static func horizontalPadding(for iconSize: Double) -> Double {
        max(8, iconSize * 0.22)
    }

    /// Horizontal padding inside a tile that is only an icon wide (on a side edge).
    public static func compactHorizontalPadding(for iconSize: Double) -> Double {
        max(3, iconSize * 0.08)
    }

    /// Vertical padding inside a tile whose height follows its content (on a side edge).
    public static func verticalPadding(for iconSize: Double) -> Double {
        max(5, iconSize * 0.12)
    }

    /// Primary text size for a tile at the given icon size.
    public static func primaryFontSize(for iconSize: Double) -> Double {
        max(12, iconSize * 0.34)
    }

    /// Secondary/caption text size.
    public static func secondaryFontSize(for iconSize: Double) -> Double {
        max(9, iconSize * 0.2)
    }
}
