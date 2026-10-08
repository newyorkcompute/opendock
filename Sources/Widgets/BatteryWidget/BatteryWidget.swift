import DockCore
import DockWidgetKit
import SwiftUI

/// Battery level, charging state and time remaining, plus battery-reporting
/// Bluetooth accessories (AirPods, Magic Mouse, ...). The settings keys are declared in
/// `BatterySettings` and listed in `docs/widgets.md`.
public enum BatteryWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.battery
    public static let displayName = "Battery"
    public static let systemImage = "battery.75percent"
    public static let summary = "Charge level and power source."
    public static let settingsSchema = BatterySettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(BatteryTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(BatteryPopoutView())
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(BatterySettingsView(instance: instance))
    }
}

/// The battery widget's settings keys.
enum BatterySettings {
    static let showPercentage = WidgetSettingKey(
        "showPercentage", type: .bool, default: "true",
        summary: "Show the charge percentage next to the ring.")
    static let showAccessories = WidgetSettingKey(
        "showAccessories", type: .bool, default: "true",
        summary: "Show small rings for Bluetooth accessories that report a battery, such as AirPods.")

    static let schema = WidgetSettingsSchema([showPercentage, showAccessories])
}
