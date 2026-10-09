import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one AirDrop tile: whether its name is shown beside the icon.
struct AirDropSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show name", isOn: updater.boolBinding(AirDropSettings.showLabel, in: $instance))
            Text("Drop files, folders, or links on the tile to AirDrop them. Click it to open AirDrop in Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
