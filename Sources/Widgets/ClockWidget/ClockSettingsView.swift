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
        _label = State(initialValue: instance.settings[ClockSettings.label] ?? "")
    }

    var body: some View {
        Form {
            Toggle("Show seconds", isOn: boolBinding(ClockSettings.showSeconds, default: false))
            Toggle("Show date", isOn: boolBinding(ClockSettings.showDate, default: true))

            Picker("Time zone", selection: stringBinding(ClockSettings.timeZone)) {
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

    private func commitLabel() {
        guard label != (instance.settings[ClockSettings.label] ?? "") else { return }
        instance.settings[ClockSettings.label] = label
        updater(instance)
    }

    private func boolBinding(_ key: String, default value: Bool) -> Binding<Bool> {
        Binding(
            get: { instance.settings[key].map { $0 == "true" } ?? value },
            set: { newValue in
                instance.settings[key] = newValue ? "true" : "false"
                updater(instance)
            }
        )
    }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { instance.settings[key] ?? "" },
            set: { newValue in
                instance.settings[key] = newValue
                updater(instance)
            }
        )
    }
}
