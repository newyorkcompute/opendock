import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock AirDrop tile: the AirDrop icon, with its name beside it unless turned off.
/// Drops are routed to `AirDropWidget.performDrop` by the dock, which also draws the ring
/// around the tile while a drag it would take is over it; this view only has to look the
/// part and open Finder's AirDrop window when clicked.
struct AirDropTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        let settings = AirDropSettings(instance: instance)
        WidgetTile {
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.04 : 0.14)) {
                icon
                if settings.showLabel {
                    WidgetPrimaryText("AirDrop")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { AirDropService.openFinderWindow() }
        .help("Drop files or links here to send them over AirDrop. Click to open AirDrop in Finder.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirDrop")
        .accessibilityHint("Drop files or links to send them. Opens AirDrop in Finder.")
        .accessibilityAddTraits(.isButton)
    }

    /// Finder's AirDrop icon, or a symbol in AirDrop's blue where the icon isn't to be found.
    @ViewBuilder
    private var icon: some View {
        let size = iconSize * 0.62
        if let image = AirDropService.icon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: size, height: size)
        }
    }
}
