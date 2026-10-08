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
            Toggle("Show percentage", isOn: updater.boolBinding(BatterySettings.showPercentage, in: $instance))
            Toggle(
                "Show accessory batteries", isOn: updater.boolBinding(BatterySettings.showAccessories, in: $instance))
        }
    }
}
