import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock Shortcuts tile: the shortcut's icon and name, which run it when clicked, and
/// a small chevron that opens the popover. With no shortcut chosen the whole tile opens the
/// popover, where one can be picked.
struct ShortcutsTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var service = ShortcutsService.shared
    /// True while a success or failure badge is up; it goes away on its own after a moment.
    @State private var showsOutcome = false

    private var settings: ShortcutsSettings { ShortcutsSettings(instance: instance) }
    private var name: String? { settings.shortcutName }
    private var state: ShortcutRunState? { name.flatMap { service.state(of: $0) } }
    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    var body: some View {
        WidgetTile {
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                if let name {
                    Button {
                        run(name)
                    } label: {
                        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                            icon
                            if settings.showName { caption(name: name) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Run \(name)")
                    .accessibilityLabel(accessibilityLabel(name: name))
                    .accessibilityHint("Runs the shortcut")
                } else {
                    icon
                    if settings.showName { caption(name: nil) }
                }
                chevron
            }
        }
        .task { await service.refresh() }
        .task(id: state) { await fadeOutcome() }
    }

    private var icon: some View {
        ShortcutIconView(
            symbol: ShortcutSymbolResolver.symbol(for: settings.symbol),
            tint: settings.tint,
            size: iconSize * 0.72,
            state: state,
            showsOutcome: showsOutcome)
    }

    /// The name with, under it, what the shortcut is doing or last did. Beside the icon on the
    /// bottom edge, under it on a side edge.
    @ViewBuilder
    private func caption(name: String?) -> some View {
        VStack(alignment: textAlignment, spacing: 0) {
            WidgetPrimaryText(name ?? "Shortcuts")
            if let name, state == nil, service.exists(name) == false {
                WidgetSecondaryText("Not found")
            } else if let state, state.isRunning || showsOutcome {
                WidgetSecondaryText(state.statusText)
            } else if name == nil {
                WidgetSecondaryText("Choose one")
            }
        }
        .frame(
            maxWidth: edge.isVertical ? nil : CGFloat(iconSize * 2.4),
            alignment: Alignment(horizontal: textAlignment, vertical: .center))
    }

    /// Not a button: a click here falls through to the dock, which opens the popover.
    private var chevron: some View {
        Image(systemName: edge.isVertical ? "chevron.right" : "chevron.down")
            .font(.system(size: max(7, iconSize * 0.16), weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(
                width: edge.isVertical ? nil : CGFloat(max(12, iconSize * 0.3)),
                height: edge.isVertical ? CGFloat(max(10, iconSize * 0.22)) : nil
            )
            .contentShape(Rectangle())
            .help("Show all shortcuts")
            .accessibilityLabel("Show all shortcuts")
    }

    private func run(_ name: String) {
        updater(settings.recording(name))
        Task { await service.run(name) }
    }

    /// Shows the badge for a finished run, then takes it down: after three seconds for a
    /// success, longer for a failure so the message can be read.
    private func fadeOutcome() async {
        guard let state, !state.isRunning else {
            showsOutcome = false
            return
        }
        showsOutcome = true
        try? await Task.sleep(for: .seconds(state.failure == nil ? 3 : 8))
        guard !Task.isCancelled else { return }
        showsOutcome = false
    }

    private func accessibilityLabel(name: String) -> String {
        if let state, state.isRunning || showsOutcome { return "\(name), \(state.statusText)" }
        return name
    }
}
