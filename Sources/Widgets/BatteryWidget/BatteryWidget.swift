import DockCore
import DockWidgetKit
import SwiftUI

/// Battery level, charging state and time remaining, plus battery-reporting
/// Bluetooth accessories (AirPods, Magic Mouse, ...).
///
/// Settings: `showPercentage` and `showAccessories` ("true"/"false", default "true").
public enum BatteryWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.battery
    public static let displayName = "Battery"
    public static let systemImage = "battery.75percent"
    public static let summary = "Charge level and power source."

    public static var defaultSettings: [String: String] {
        [
            BatterySettings.showPercentage: "true",
            BatterySettings.showAccessories: "true",
        ]
    }

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

/// Setting keys and parsing helpers shared by the battery views.
enum BatterySettings {
    static let showPercentage = "showPercentage"
    static let showAccessories = "showAccessories"

    static func bool(_ key: String, in instance: WidgetInstance, default value: Bool = true) -> Bool {
        guard let raw = instance.settings[key] else { return value }
        return raw != "false"
    }
}
