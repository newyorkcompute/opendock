import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// One minimized window, in the section before the Trash. A thumbnail when Screen
/// Recording was already allowed and a capture succeeded; otherwise the app's icon with
/// a small window glyph. Clicking restores it. The menu is the controller's, opened on
/// right-click the same way an app's menu is.
struct MinimizedWindowItemView: View {
    let window: MinimizedDockWindow
    let controller: DockController

    @Environment(\.dockIconSize) private var iconSize

    var body: some View {
        DockBaselineStack {
            icon
        } indicator: {
            Color.clear.frame(width: 4, height: 4) // keep baseline aligned with apps
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.restoreMinimizedWindow(window) }
        // One element: the thumbnail and the window glyph aren't separate items.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.label)
        .accessibilityHint("Restores the window")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { controller.restoreMinimizedWindow(window) }
        // Right-clicks open the menu through the controller (see `installContextClickMonitor`).
        .accessibilityAction(.showMenu) { controller.showMinimizedWindowMenu(for: window) }
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail = controller.minimizedWindows.thumbnail(for: window.id) {
            // A square slot, like an icon, so a wide window doesn't stretch the row.
            // The layout magnifies it the same way it magnifies `dockIcon`.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(idealWidth: iconSize, idealHeight: iconSize)
                .overlay {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(iconSize * 0.08)
                }
                .background {
                    RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous)
                        .fill(.black.opacity(0.25))
                }
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous)
                        .strokeBorder(.primary.opacity(0.28), lineWidth: 1)
                }
        } else {
            Image(nsImage: AppIconProvider.shared.icon(for: window.app.url))
                .dockIcon(restingSize: iconSize)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "macwindow")
                        .font(.system(size: iconSize * 0.26, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(iconSize * 0.04)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(iconSize * 0.04)
                }
        }
    }
}
