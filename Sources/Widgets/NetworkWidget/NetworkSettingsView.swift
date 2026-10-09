import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one network tile: which speeds it shows, the unit, and which interface
/// it measures.
struct NetworkSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var monitor = NetworkActivityMonitor.shared

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    private var selection: NetworkInterfaceSelection { NetworkSettings.selection(in: instance) }

    var body: some View {
        Form {
            Toggle("Show download", isOn: updater.boolBinding(NetworkSettings.showDownload, in: $instance))
            Toggle("Show upload", isOn: updater.boolBinding(NetworkSettings.showUpload, in: $instance))
            Toggle("Show history", isOn: updater.boolBinding(NetworkSettings.showHistory, in: $instance))

            Picker("Unit", selection: updater.stringBinding(NetworkSettings.unit, in: $instance)) {
                Text("Bytes (KB/s, MB/s)").tag(NetworkRateUnit.bytes.rawValue)
                Text("Bits (Kb/s, Mb/s)").tag(NetworkRateUnit.bits.rawValue)
            }

            Picker("Interface", selection: updater.stringBinding(NetworkSettings.interface, in: $instance)) {
                Text("All connected").tag("")
                ForEach(interfaceChoices) { choice in
                    Text(choice.title).tag(choice.name)
                }
            }

            WidgetCaption("The tile shows both speeds when both are turned off.")
        }
        .onAppear { monitor.refreshIfStale() }
    }

    /// The interfaces the Mac has now, plus the saved one if it isn't among them so the
    /// picker can still show (and change) it.
    private var interfaceChoices: [InterfaceChoice] {
        var choices = monitor.snapshot.listedInterfaces(selection: selection).map {
            InterfaceChoice(name: $0.name, title: $0.title)
        }
        if case let .named(name) = selection, !choices.contains(where: { $0.name == name }) {
            choices.append(InterfaceChoice(name: name, title: "\(name) (not connected)"))
        }
        return choices
    }
}

private struct InterfaceChoice: Identifiable {
    let name: String
    let title: String
    var id: String { name }
}
