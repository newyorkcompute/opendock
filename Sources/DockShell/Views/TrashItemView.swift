import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The Trash at the end of the dock, like Apple's Dock's: its icon shows whether it's
/// empty, clicking it opens the Trash in Finder, and drops on it go to the Trash (files)
/// or out of the dock (items). Its menu, and right-clicks, are handled by `DockController`
/// (see `DockController+Trash.swift`), which also keeps `TrashMonitor` running while the
/// Trash is shown.
struct TrashItemView: View {
    let controller: DockController

    @Environment(TrashMonitor.self) private var trash
    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The system's own Trash icons, the ones Finder and Apple's Dock show.
    private static let emptyIcon = NSImage(named: NSImage.trashEmptyName)
    private static let fullIcon = NSImage(named: NSImage.trashFullName)

    private var icon: NSImage {
        (trash.isEmpty ? Self.emptyIcon : Self.fullIcon) ?? AppIconProvider.shared.icon(for: trash.url)
    }

    var body: some View {
        DockBaselineStack {
            Image(nsImage: icon)
                .dockIcon(restingSize: iconSize)
                .overlay {
                    if shellState.isDragOverTrash {
                        RoundedRectangle(cornerRadius: iconSize * 0.22 + 3, style: .continuous)
                            .strokeBorder(.primary.opacity(0.7), lineWidth: 2)
                            .padding(-3)
                            .allowsHitTesting(false)
                    }
                }
                .modifier(
                    HeadShakeEffect(trigger: shellState.trashShakes, distance: reduceMotion ? 0 : iconSize * 0.12))
        } indicator: {
            Color.clear.frame(width: 4, height: 4) // keep baseline aligned with apps
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.openTrash() }
        .accessibilityLabel("Trash")
        .accessibilityValue(trash.isKnown ? (trash.isEmpty ? "Empty" : "Full") : "")
        // Right-clicks open the menu through the controller (see `installContextClickMonitor`).
        .accessibilityAction(.showMenu) { controller.showTrashMenu() }
    }
}

/// Shakes a view from side to side, the way a password field says no, each time `trigger`
/// changes. `distance` is how far it swings; zero (for Reduce Motion) keeps it still.
private struct HeadShakeEffect: ViewModifier {
    let trigger: Int
    let distance: CGFloat

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-distance, duration: 0.06)
                CubicKeyframe(distance, duration: 0.08)
                CubicKeyframe(-distance * 0.6, duration: 0.08)
                CubicKeyframe(distance * 0.6, duration: 0.08)
                CubicKeyframe(0, duration: 0.08)
            }
        }
    }
}
