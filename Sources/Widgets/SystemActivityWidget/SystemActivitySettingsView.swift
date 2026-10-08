import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one system activity tile: which metrics it shows, and how CPU is drawn.
struct SystemActivitySettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show CPU", isOn: binding(SystemActivitySettings.showCPU))
            Toggle("Show memory", isOn: binding(SystemActivitySettings.showMemory))
            Toggle("Show disk", isOn: binding(SystemActivitySettings.showDisk))
            Toggle("Show CPU history", isOn: binding(SystemActivitySettings.showCPUHistory))
            Text("The tile shows CPU when every metric is turned off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { SystemActivitySettings.bool(key, in: instance) },
            set: { newValue in
                instance.settings[key] = newValue ? "true" : "false"
                updater(instance)
            }
        )
    }
}
