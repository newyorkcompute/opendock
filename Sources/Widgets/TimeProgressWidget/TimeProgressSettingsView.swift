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
            WidgetCaption("The tile shows the day when every period is turned off.")

            Picker(
                "Style",
                selection: updater.choiceBinding(
                    TimeProgressSettings.style, in: $instance, default: TimeProgressSettings.Style.bars)
            ) {
                Text("Bars").tag(TimeProgressSettings.Style.bars)
                Text("Rings").tag(TimeProgressSettings.Style.rings)
            }
        }
    }
}
