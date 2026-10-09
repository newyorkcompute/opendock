import DockCore
import DockWidgetKit
import SwiftUI

/// Runs a macOS Shortcut from the dock: the tile shows the shortcut's icon and name and a
/// click runs it, through the `shortcuts` command-line tool, without bringing the Shortcuts
/// app to the front. The popover lists the shortcuts run recently and every other one.
/// The settings keys are declared in `ShortcutsSettings` and listed in `docs/widgets.md`.
public enum ShortcutsWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.shortcuts
    public static let displayName = "Shortcuts"
    public static let systemImage = "square.on.square"
    public static let summary = "A shortcut that runs when you click it."
    public static let settingsSchema = ShortcutsSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(ShortcutsTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(ShortcutsPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(ShortcutsSettingsView(instance: instance))
    }
}

/// The Shortcuts widget's settings keys, and typed access to one instance's values.
struct ShortcutsSettings {
    static let shortcut = WidgetSettingKey(
        "shortcut", type: .text, default: "",
        summary:
            "The name of the shortcut the tile runs, exactly as the Shortcuts app shows it. Empty means none is chosen yet; the popover still lists every shortcut."
    )
    static let symbol = WidgetSettingKey(
        "symbol", type: .text, default: "",
        summary:
            "The SF Symbol drawn on the tile, such as `\"bolt.fill\"`. Empty, or a name this Mac doesn't have, draws the default sparkles."
    )
    static let color = WidgetSettingKey(
        "color", type: .choice(ShortcutTint.allCases.map(\.rawValue)), default: ShortcutTint.default.rawValue,
        summary: "The color behind the symbol, like the icon colors in the Shortcuts app.")
    static let showName = WidgetSettingKey(
        "showName", type: .bool, default: "true",
        summary: "Show the shortcut's name beside the icon. When off, the tile is just the icon.")
    static let recents = WidgetSettingKey(
        "recents", type: .text, default: "",
        summary:
            "The shortcuts last run from this tile, newest first, one name per line. The tile keeps this up to date; there's no need to edit it."
    )

    static let schema = WidgetSettingsSchema([shortcut, symbol, color, showName, recents])

    let instance: WidgetInstance

    /// The chosen shortcut's name, or `nil` when none is chosen.
    var shortcutName: String? {
        let name = Self.shortcut.value(in: instance.settings).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var symbol: String { Self.symbol.value(in: instance.settings) }
    var tint: ShortcutTint { ShortcutTint(rawValue: Self.color.value(in: instance.settings)) ?? .default }
    var showName: Bool { Self.showName.boolValue(in: instance.settings) }
    var recents: [String] { ShortcutHistory.names(from: Self.recents.value(in: instance.settings)) }

    /// `instance` with `name` recorded as the latest run.
    func recording(_ name: String) -> WidgetInstance {
        var copy = instance
        copy.settings[Self.recents.name] = ShortcutHistory.stored(ShortcutHistory.adding(name, to: recents))
        return copy
    }
}
