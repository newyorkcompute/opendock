import DockCore
import SwiftUI

/// The contract every widget implements. A widget is a *type*; the dock holds
/// `WidgetInstance`s (type ID + settings) and asks the registry to render them.
///
/// Widgets are SwiftUI views. They should:
/// - size themselves to `\.dockIconSize` in height (use `WidgetTile` for the standard pill),
/// - do their own polling, and stop/slow it when `\.dockIsVisible` is false,
/// - persist settings through `\.widgetUpdateSettings`, never through their own files.
public protocol DockWidget {
    /// Stable reverse-DNS identifier, e.g. `com.newyorkcompute.opendock.widget.clock`. Never change it.
    static var typeID: String { get }
    /// Shown in the widget picker and context menus.
    static var displayName: String { get }
    /// SF Symbol for the picker.
    static var systemImage: String { get }
    /// One-line description for the picker.
    static var summary: String { get }

    /// Default settings for a freshly added instance.
    static var defaultSettings: [String: String] { get }

    /// The compact view that lives in the dock.
    static func makeView(instance: WidgetInstance) -> AnyView

    /// Optional larger view shown in a popover when the widget is clicked.
    /// Return `nil` for widgets that have nothing more to show.
    static func makePopout(instance: WidgetInstance) -> AnyView?

    /// Optional settings UI, shown in the app's Settings window for this instance.
    static func makeSettingsView(instance: WidgetInstance) -> AnyView?
}

public extension DockWidget {
    static var defaultSettings: [String: String] { [:] }
    static func makePopout(instance: WidgetInstance) -> AnyView? { nil }
    static func makeSettingsView(instance: WidgetInstance) -> AnyView? { nil }

    /// Convenience for creating a new instance of this widget with its defaults.
    static func makeInstance() -> WidgetInstance {
        WidgetInstance(typeID: typeID, settings: defaultSettings)
    }
}
