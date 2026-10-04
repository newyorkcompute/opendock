import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one battery tile.
struct BatterySettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show percentage", isOn: binding(BatterySettings.showPercentage))
            Toggle("Show accessory batteries", isOn: binding(BatterySettings.showAccessories))
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { BatterySettings.bool(key, in: instance) },
            set: { newValue in
                instance.settings[key] = newValue ? "true" : "false"
                updater(instance)
            }
        )
    }
}
