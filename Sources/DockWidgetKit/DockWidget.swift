import DockCore
import SwiftUI

/// The contract every widget implements. A widget is a *type*; the dock holds
/// `WidgetInstance`s (type ID + settings) and asks the registry to render them.
///
/// Widgets are SwiftUI views. They should:
/// - size themselves to `\.dockIconSize` in height (use `WidgetTile` for the standard pill),
/// - do their own polling, and stop/slow it when `\.dockIsVisible` is false,
/// - ask for permissions on their own only while `\.widgetsMayRequestAccess` is true,
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

    /// The settings keys this widget reads, with their types, defaults, and allowed values.
    /// It's the one source for the settings UI, for validation when a `dock.json` is
    /// loaded, and for `docs/widgets.md`. Widgets without settings leave it empty.
    static var settingsSchema: WidgetSettingsSchema { get }

    /// Default settings for a freshly added instance. By default, the schema's defaults.
    static var defaultSettings: [String: String] { get }

    /// The compact view that lives in the dock.
    static func makeView(instance: WidgetInstance) -> AnyView

    /// Optional larger view shown in a popover when the widget is clicked.
    /// Return `nil` for widgets that have nothing more to show.
    static func makePopout(instance: WidgetInstance) -> AnyView?

    /// Optional settings UI, shown in the app's Settings window for this instance.
    static func makeSettingsView(instance: WidgetInstance) -> AnyView?

    /// Whether the tile takes `drop`, dragged over it from Finder or another app. While it
    /// does, the dock highlights the tile instead of opening a gap in the row, and a release
    /// there calls `performDrop`. The dock handles drops itself (SwiftUI drop destinations
    /// inside the dock don't work), so widgets declare them here rather than with `onDrop`.
    /// By default a widget takes nothing.
    static func acceptsDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool

    /// `drop` was released on the tile. Returns whether it was taken; the dock beeps if not.
    static func performDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool
}

public extension DockWidget {
    static var settingsSchema: WidgetSettingsSchema { WidgetSettingsSchema() }
    static var defaultSettings: [String: String] { settingsSchema.defaults }
    static func makePopout(instance: WidgetInstance) -> AnyView? { nil }
    static func makeSettingsView(instance: WidgetInstance) -> AnyView? { nil }
    static func acceptsDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool { false }
    static func performDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool { false }

    /// Convenience for creating a new instance of this widget with its defaults.
    static func makeInstance() -> WidgetInstance {
        WidgetInstance(typeID: typeID, settings: defaultSettings)
    }
}
