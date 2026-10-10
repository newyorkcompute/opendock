import DockCore
import SwiftUI

/// A thin line across the dock, like the Dock's separators, centered in a slot long enough
/// to aim at. Used for divider items and before unpinned running apps.
struct DockDivider: View {
    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        let line = edge.axis.size(length: 1, thickness: iconSize * 0.8)
        // As thick as an app item (icon plus running indicator), so the line sits
        // centered on the row of icons.
        let slot = edge.axis.size(length: max(12, iconSize * 0.3), thickness: iconSize + 6)
        Capsule()
            .fill(.primary.opacity(0.22))
            .frame(width: line.width, height: line.height)
            .frame(width: slot.width, height: slot.height)
            .contentShape(Rectangle())
    }
}

/// A divider the user placed. Clicking it opens the divider menu (right-click and
/// control-click are handled by `DockController`, see `installContextClickMonitor`).
struct DividerItemView: View {
    let item: DockItem
    let controller: DockController

    var body: some View {
        DockDivider()
            .onTapGesture { controller.showDividerMenu(for: item.id) }
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { controller.showDividerMenu(for: item.id) }
    }
}
