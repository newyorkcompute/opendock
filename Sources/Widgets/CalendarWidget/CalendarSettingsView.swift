import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one calendar tile.
struct CalendarSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    var body: some View {
        Form {
            Toggle(
                "Show next event",
                isOn: Binding(
                    get: { CalendarSettings.showNextEvent(in: instance) },
                    set: { newValue in
                        instance.settings[CalendarSettings.showNextEvent] = newValue ? "true" : "false"
                        updater(instance)
                    }
                ))
        }
    }
}
