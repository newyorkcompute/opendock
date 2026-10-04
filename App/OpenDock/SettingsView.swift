import DockCore
import SwiftUI

/// Placeholder; the real settings window replaces this.
struct SettingsView: View {
    @Environment(DockStore.self) private var store

    var body: some View {
        Form {
            Slider(
                value: Binding(
                    get: { store.settings.iconSize },
                    set: { value in store.updateSettings { $0.iconSize = value } }
                ),
                in: DockSettings.iconSizeRange
            ) {
                Text("Icon size")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 200)
    }
}
