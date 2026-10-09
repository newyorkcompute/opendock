import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// A place to drop things to AirDrop them: files and folders from Finder, or links from a
/// browser. Dropping opens the AirDrop sheet with the devices nearby; clicking the tile
/// opens the AirDrop window in Finder. The settings keys are declared in `AirDropSettings`
/// and listed in `docs/widgets.md`.
public enum AirDropWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.airDrop
    public static let displayName = "AirDrop"
    public static let systemImage = "dot.radiowaves.left.and.right"
    public static let summary = "Drop files or links on it to send them over AirDrop."
    public static let settingsSchema = AirDropSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(AirDropTileView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(AirDropSettingsView(instance: instance))
    }

    public static func acceptsDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool {
        !payload(of: drop).isEmpty
    }

    public static func performDrop(_ drop: WidgetDrop, instance: WidgetInstance) -> Bool {
        AirDropService.send(payload(of: drop).items)
    }

    /// What of `drop` AirDrop would send.
    static func payload(of drop: WidgetDrop) -> AirDropPayload {
        AirDropPayload(urls: drop.urls, texts: drop.texts)
    }
}

/// The widget's settings keys, and typed access to one instance's values.
struct AirDropSettings {
    static let showLabel = WidgetSettingKey(
        "showLabel", type: .bool, default: "true",
        summary: "Show the name AirDrop beside the icon. Off, the tile is the icon alone.")

    static let schema = WidgetSettingsSchema([showLabel])

    let instance: WidgetInstance

    var showLabel: Bool { Self.showLabel.boolValue(in: instance.settings) }
}
