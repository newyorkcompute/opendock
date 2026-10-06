import DockCore
import SwiftUI

/// A thin vertical line, like the Dock's separators, centered in a slot wide enough to
/// aim at. Used for divider items and before unpinned running apps.
struct DockDivider: View {
    @Environment(\.dockIconSize) private var iconSize

    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.22))
            .frame(width: 1, height: iconSize * 0.8)
            // As tall as an app item (icon plus running indicator), so the line sits
            // centered on the row of icons.
            .frame(width: max(12, iconSize * 0.3), height: iconSize + 6)
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
    }
}
