import AppKit
import DockCore
import DockShell
import SwiftUI

/// Chooses the display the dock lives on. Lists displays as they're connected and
/// disconnected, and keeps showing a chosen display while it's away.
struct DisplayPicker: View {
    @Environment(DockStore.self) private var store
    @State private var screens: [DockPlacement.Screen] = []

    private enum Choice: Hashable {
        case main
        case active
        case specific(String)
    }

    var body: some View {
        Picker("Display", selection: selection) {
            Text("Main display").tag(Choice.main)
            Text("Display with the active menu bar").tag(Choice.active)
            Divider()
            ForEach(screens.filter { $0.id != nil }, id: \.id) { screen in
                Text(screen.name).tag(Choice.specific(screen.id ?? ""))
            }
            if let missing = disconnectedChoice {
                Text("\(missing.name.isEmpty ? "Display" : missing.name) (disconnected)")
                    .tag(Choice.specific(missing.id))
            }
        }
        .task {
            refresh()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                refresh()
            }
        }

        if disconnectedChoice != nil {
            Text("The dock is on the main display until this display is connected again.")
                .settingsFootnote()
        }
    }

    private func refresh() {
        screens = NSScreen.screens.map(\.placementScreen)
    }

    /// The chosen display, when it isn't connected.
    private var disconnectedChoice: (id: String, name: String)? {
        guard case let .specific(id, name) = store.settings.display,
              !screens.contains(where: { $0.id == id }) else { return nil }
        return (id, name)
    }

    private var selection: Binding<Choice> {
        Binding(
            get: {
                switch store.settings.display {
                case .main: .main
                case .active: .active
                case let .specific(id, _): .specific(id)
                }
            },
            set: { choice in
                let display: DockSettings.Display = switch choice {
                case .main: .main
                case .active: .active
                case let .specific(id):
                    .specific(id: id, name: screens.first { $0.id == id }?.name ?? disconnectedChoice?.name ?? "")
                }
                store.updateSettings { $0.display = display }
            }
        )
    }
}
