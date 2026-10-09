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
            Toggle("Show CPU", isOn: updater.boolBinding(SystemActivitySettings.showCPU, in: $instance))
            Toggle("Show memory", isOn: updater.boolBinding(SystemActivitySettings.showMemory, in: $instance))
            Toggle("Show disk", isOn: updater.boolBinding(SystemActivitySettings.showDisk, in: $instance))
            Toggle("Show CPU history", isOn: updater.boolBinding(SystemActivitySettings.showCPUHistory, in: $instance))
            WidgetCaption("The tile shows CPU when every metric is turned off.")
        }
    }
}
