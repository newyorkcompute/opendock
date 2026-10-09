import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one reminders tile: which list, which reminders, and whether to name the list.
struct RemindersSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var service = RemindersService.shared

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    private var settings: RemindersSettings { RemindersSettings(instance: instance) }

    var body: some View {
        Form {
            Picker("List", selection: listBinding) {
                Text("All Lists").tag("")
                if !service.lists.isEmpty {
                    Divider()
                    ForEach(service.lists) { list in
                        Label {
                            Text(list.title)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color(hex: list.colorHex))
                                .imageScale(.small)
                        }
                        .tag(list.id)
                    }
                }
            }

            Picker(
                "Show",
                selection: updater.choiceBinding(RemindersSettings.scope, in: $instance, default: ReminderScope.all)
            ) {
                Text("All reminders").tag(ReminderScope.all)
                Text("Due today and overdue").tag(ReminderScope.today)
            }

            Toggle("Show list name", isOn: updater.boolBinding(RemindersSettings.showListName, in: $instance))

            accessStatus
        }
        .onAppear { service.refresh(force: true) }
    }

    @ViewBuilder
    private var accessStatus: some View {
        if service.isUndetermined {
            LabeledContent("Reminders access") {
                Button("Allow") {
                    Task { await service.requestAccess() }
                }
            }
        } else if service.isDenied {
            LabeledContent("Reminders access") {
                Button("Open Privacy Settings") { SystemSettingsPane.reminders.open() }
            }
            WidgetCaption("Reminders access is off, so the tile can't show your lists.")
        }
    }

    // MARK: Bindings

    /// A stored list that isn't on this Mac shows as "All Lists", which is what the tile does with it.
    private var listBinding: Binding<String> {
        Binding(
            get: { settings.list(in: service.lists)?.id ?? "" },
            set: { newValue in
                instance.settings[RemindersSettings.listID.name] = newValue
                updater(instance)
            }
        )
    }
}
