import DockCore
import DockWidgetKit
import ScriptedWidgetRuntime
import SwiftUI

/// A tile that runs a widget written in JavaScript: a folder with a `manifest.json` and a
/// `main.js` in `~/Library/Application Support/OpenDock/Widgets`. The script describes its
/// tile as data (text, numbers, rings, icons, sparklines in rows and columns) and OpenDock
/// draws it with the same views the built-in widgets use. Which package a tile runs is its
/// `package` setting; the package's own settings, declared in its manifest, live beside it.
/// The format and the API are documented in `docs/scripted-widgets.md`.
public enum ScriptedWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.scripted
    public static let displayName = "Scripted Widget"
    public static let systemImage = "curlybraces"
    public static let summary = "A widget written in JavaScript, from your Widgets folder."
    public static let settingsSchema = ScriptedWidgetSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(ScriptedTileView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(ScriptedSettingsView(instance: instance))
    }
}

/// The host's own settings key, and typed access to one instance's values.
struct ScriptedWidgetSettings {
    static let package = WidgetSettingKey(
        "package", type: .text, default: "",
        summary:
            "The `id` from the manifest of the installed scripted widget this tile runs, as chosen in Settings. Empty means none is chosen yet. The widget's own settings, declared in its manifest, are stored beside this key under their own names."
    )

    static let schema = WidgetSettingsSchema([package])

    let instance: WidgetInstance

    /// The chosen package's id, or nil when none is chosen.
    var packageID: String? {
        let id = Self.package.value(in: instance.settings).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }
}
