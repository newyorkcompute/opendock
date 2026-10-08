import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one clock tile.
struct ClockSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var label: String

    private static let zoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
        _label = State(initialValue: ClockSettings.label.value(in: instance.settings))
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

            TextField("Label (replaces the date)", text: $label)
                .onSubmit(commitLabel)
        }
        .onDisappear(perform: commitLabel)
    }

    /// The label is committed on submit and when the view goes away, not on every
    /// keystroke, so typing doesn't write the file over and over.
    private func commitLabel() {
        guard label != ClockSettings.label.value(in: instance.settings) else { return }
        instance.settings[ClockSettings.label.name] = label
        updater(instance)
    }
}
