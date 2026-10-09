import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one time progress tile: which periods it shows, and how it draws them.
struct TimeProgressSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Year", isOn: updater.boolBinding(TimeProgressSettings.showYear, in: $instance))
            Toggle("Month", isOn: updater.boolBinding(TimeProgressSettings.showMonth, in: $instance))
            Toggle("Week", isOn: updater.boolBinding(TimeProgressSettings.showWeek, in: $instance))
            Toggle("Day", isOn: updater.boolBinding(TimeProgressSettings.showDay, in: $instance))
            Text("The tile shows the day when every period is turned off.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Style", selection: styleBinding) {
                Text("Bars").tag(TimeProgressSettings.Style.bars)
                Text("Rings").tag(TimeProgressSettings.Style.rings)
            }
        }
    }

    private var styleBinding: Binding<TimeProgressSettings.Style> {
        Binding(
            get: { TimeProgressSettings(instance: instance).style },
            set: { newValue in
                instance.settings[TimeProgressSettings.style.name] = newValue.rawValue
                updater(instance)
            }
        )
    }
}
