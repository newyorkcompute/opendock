import DockCore
import DockWidgetKit
import SwiftUI

/// The widget library: every registered widget, with a button to add it to the dock.
struct WidgetsTab: View {
    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry

    var body: some View {
        Form {
            Section {
                ForEach(registry.descriptors) { descriptor in
                    WidgetLibraryRow(
                        descriptor: descriptor,
                        countInDock: count(of: descriptor.typeID)
                    ) {
                        DockItemActions.addWidget(descriptor.typeID, registry: registry, to: store)
                    }
                }
            } header: {
                Text("Widget Library")
            } footer: {
                Text(
                    "Widgets are added to the end of the dock. Rearrange them in Dock Items, or drag them in the dock itself."
                )
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    private func count(of typeID: String) -> Int {
        store.items.count { $0.widgetInstance?.typeID == typeID }
    }
}

/// A single widget in the library list.
private struct WidgetLibraryRow: View {
    let descriptor: WidgetDescriptor
    let countInDock: Int
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: descriptor.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName)
                    .font(.headline)
                Text(descriptor.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if countInDock > 0 {
                    Text(countInDock == 1 ? "In your dock" : "In your dock \(countInDock) times")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)

            Button("Add to Dock", action: add)
        }
        .padding(.vertical, 2)
    }
}
