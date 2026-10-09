import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one clock tile.
struct ClockSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    private static let zoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle("Show seconds", isOn: updater.boolBinding(ClockSettings.showSeconds, in: $instance))
            Toggle("Show date", isOn: updater.boolBinding(ClockSettings.showDate, in: $instance))

            Picker("Time zone", selection: updater.stringBinding(ClockSettings.timeZone, in: $instance)) {
                Text("System").tag("")
                ForEach(Self.zoneIdentifiers, id: \.self) { id in
                    Text(id.replacingOccurrences(of: "_", with: " ")).tag(id)
                }
            }

            WidgetTextSetting("Label (replaces the date)", key: ClockSettings.label, instance: $instance)
        }
    }
}
