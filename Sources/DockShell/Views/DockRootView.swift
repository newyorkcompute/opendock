import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Root of the panel's view hierarchy. Reports its natural size to the controller,
/// wires environment values, and renders the dock surface.
struct DockRootView: View {
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(DockShellState.self) private var shellState

    var body: some View {
        DockSurfaceView(controller: controller)
            .fixedSize()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                shellState.geometry.containerOrigin = frame.origin
                controller.contentSizeChanged(frame.size)
            }
            .environment(\.dockIconSize, store.settings.iconSize)
            .environment(\.dockEdge, store.settings.edge)
            .environment(\.dockIsVisible, shellState.isVisible)
            .environment(\.widgetsMayRequestAccess, !store.needsWelcome)
            .onChange(of: store.settings.autoHide) { _, enabled in
                controller.autoHideSettingChanged(enabled)
            }
            .onChange(of: store.settings.revealInFullScreen) {
                controller.fullScreenRevealSettingChanged()
            }
            .onChange(of: store.settings.display) {
                controller.displaySettingChanged()
            }
            .onChange(of: store.settings.edge) {
                controller.edgeSettingChanged()
            }
            .onChange(of: shellState.interactionDepth) { old, new in
                if old > 0, new == 0 { controller.interactionEnded() }
            }
            .onChange(of: store.settings.showBadges, initial: true) { _, enabled in
                controller.badges.isEnabled = enabled
            }
            .onChange(of: store.settings.showRecentApps, initial: true) { _, enabled in
                controller.recentAppsSettingChanged(enabled)
            }
            .onChange(of: store.showsTrash, initial: true) { _, shown in
                controller.trashShownChanged(shown)
            }
            .onChange(of: store.needsWelcome, initial: true) { _, needsWelcome in
                // Like widgets, the Trash doesn't prompt for anything before the welcome window closes.
                controller.trash.setMayAskFinder(!needsWelcome)
            }
            .onChange(of: shellState.isVisible, initial: true) { _, visible in
                controller.badges.isDockVisible = visible
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: store.settings.edge.alignment)
    }
}

/// The visible dock: material background, the row of items, and the hovered item's label,
/// all placed by `DockMagnifyingLayout`.
struct DockSurfaceView: View {
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry
    @Environment(DockShellState.self) private var shellState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = DockRowMetrics(settings: store.settings)
        let extras = controller.runningSection
        let recents = controller.recentSection
        let showsTrash = store.showsTrash
        let rowIDs =
            store.items.map { DockRowItemID.pinned($0.id) } + extras.map { DockRowItemID.running($0.id) }
            + recents.map { DockRowItemID.recent($0.id) } + (showsTrash ? [DockRowItemID.trash] : [])
        // The Trash has a divider before it unless the row already ends with one.
        let trashDivider = showsTrash && !(extras.isEmpty && recents.isEmpty && store.items.last?.isDivider == true)
        DockMagnifyingLayout(
            metrics: metrics,
            pointer: shellState.pointer,
            selectedID: shellState.isPointerInside ? nil : shellState.keyboardSelection,
            amount: shellState.magnification,
            // A profile's name is centered over the dock rather than over an item.
            hoveredID: shellState.profileBanner == nil ? shellState.hoveredItemID : nil,
            draggedID: shellState.draggingRowID,
            gap: shellState.dropGap,
            geometry: shellState.geometry
        ) {
            DockHitZone()
                .dockLayoutRole(.hitZone)

            surface(cornerRadius: metrics.cornerRadius)
                .dockLayoutRole(.surface)

            ForEach(store.items) { item in
                DockItemView(item: item, controller: controller)
                    .keyboardSelection(shellState.keyboardSelection == .pinned(item.id))
                    .transition(profileSwap(metrics))
                    .dockLayoutRole(
                        .item(
                            .pinned(item.id),
                            growth: DockMagnification.growth(for: item),
                            hoverable: !item.isSpacer && !item.isDivider
                        ))
            }

            if store.items.isEmpty {
                EmptyProfilePlaceholder(controller: controller)
                    .transition(profileSwap(metrics))
                    .dockLayoutRole(.item(nil, growth: 0, hoverable: false))
            }

            if !extras.isEmpty {
                DockDivider()
                    .dockLayoutRole(.item(nil, growth: 0, hoverable: false))
                    .transition(.dockRunningApp(edge: metrics.edge))
                ForEach(extras) { extra in
                    SectionAppItemView(app: extra.app, rowID: .running(extra.id), controller: controller)
                        .keyboardSelection(shellState.keyboardSelection == .running(extra.id))
                        .dockLayoutRole(.item(.running(extra.id), growth: 1, hoverable: true))
                        .transition(.dockRunningApp(edge: metrics.edge))
                }
            }

            if !recents.isEmpty {
                DockDivider()
                    .dockLayoutRole(.item(nil, growth: 0, hoverable: false))
                    .transition(.dockRunningApp(edge: metrics.edge))
                ForEach(recents) { recent in
                    SectionAppItemView(app: recent.app, rowID: .recent(recent.id), controller: controller)
                        .keyboardSelection(shellState.keyboardSelection == .recent(recent.id))
                        .dockLayoutRole(.item(.recent(recent.id), growth: 1, hoverable: true))
                        .transition(.dockRunningApp(edge: metrics.edge))
                }
            }

            if trashDivider {
                DockDivider()
                    .dockLayoutRole(.item(nil, growth: 0, hoverable: false))
                    .transition(.dockRunningApp(edge: metrics.edge))
            }
            if showsTrash {
                TrashItemView(controller: controller)
                    .keyboardSelection(shellState.keyboardSelection == .trash)
                    .dockLayoutRole(.item(.trash, growth: 1, hoverable: true))
                    .transition(.dockRunningApp(edge: metrics.edge))
            }

            DockItemLabel(
                title: shellState.profileBanner
                    ?? label(for: shellState.hoveredItemID, extras: extras, recents: recents),
                truncates: metrics.edge.isVertical
            )
            .dockLayoutRole(.label)
        }
        // Running and recent apps come and go with the same animation; one value covers both
        // sections (and the Trash), so an app moving from one to the other is a single change.
        .animation(
            .dockRunningApps,
            value: extras.map { DockRowItemID.running($0.id) } + recents.map { DockRowItemID.recent($0.id) }
                + (showsTrash ? [DockRowItemID.trash] : [])
        )
        .onChange(of: rowIDs) {
            controller.keyboardRowChanged()
        }
        .onContinuousHover { phase in
            controller.pointerHoverChanged(phase)
        }
    }

    private func surface(cornerRadius: CGFloat) -> some View {
        DockMaterialBackground(material: store.settings.material, cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            // The glass fill isn't hit-testable on its own; make the whole surface a target
            // so right-click lands on the padding, not just on items.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contextMenu { DockBackgroundMenu(controller: controller) }
    }

    private func profileSwap(_ metrics: DockRowMetrics) -> AnyTransition {
        .dockProfileSwap(
            direction: shellState.profileSwapDirection, distance: metrics.iconSize, edge: metrics.edge,
            reduceMotion: reduceMotion)
    }

    private func label(for id: DockRowItemID?, extras: [RunningDockApp], recents: [RecentDockApp]) -> String? {
        switch id {
        case nil:
            return nil
        case let .pinned(id):
            switch store.items.first(where: { $0.id == id })?.kind {
            case let .app(app): return app.displayName
            case let .folder(folder): return folder.displayName
            case let .widget(instance): return registry.displayName(for: instance)
            case .spacer, .divider, .trash, nil: return nil
            }
        case let .running(id):
            return extras.first { $0.id == id }?.app.displayName
        case let .recent(id):
            return recents.first { $0.id == id }?.app.displayName
        case .trash:
            return "Trash"
        }
    }
}

extension AnyTransition {
    /// Running apps grow in from the baseline as they launch and shrink away as they quit,
    /// while their neighbors slide over. Recent apps come and go the same way.
    static func dockRunningApp(edge: DockSettings.Edge) -> AnyTransition {
        .scale(scale: 0.4, anchor: edge.unitPoint).combined(with: .opacity)
    }
}

extension Animation {
    static let dockRunningApps = Animation.easeInOut(duration: 0.25)
}

/// Keeps the pointer "on the dock" between and above magnified icons. Nearly transparent
/// rather than clear: the window server lets events through fully transparent pixels.
struct DockHitZone: View {
    var body: some View {
        Rectangle().fill(.black.opacity(0.005))
    }
}

/// Stands in for the items of an empty profile, so the dock keeps its height and shows
/// where to start. Clicking it adds apps.
struct EmptyProfilePlaceholder: View {
    let controller: DockController

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: iconSize * 0.36, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: iconSize, height: iconSize)
            .padding(edge.facingSide, 6) // keep baseline aligned with apps
            .contentShape(Rectangle())
            .onTapGesture { controller.promptForApp() }
            .help("Add apps to this profile")
            .accessibilityLabel("Add App")
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// Marks the item the keyboard has selected: a ring around it, and the selected trait
    /// for VoiceOver.
    func keyboardSelection(_ isSelected: Bool) -> some View {
        modifier(DockKeyboardSelectionModifier(isSelected: isSelected))
    }
}

private struct DockKeyboardSelectionModifier: ViewModifier {
    let isSelected: Bool

    @Environment(\.dockIconSize) private var iconSize

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: iconSize * 0.22 + 3, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The item name beside the hovered icon, away from the screen edge, like the Dock's labels.
struct DockItemLabel: View {
    let title: String?
    /// Beside a side-edge dock the label can't grow without limit: the layout proposes
    /// `DockRowMetrics.labelMaxWidth` and longer names are truncated in the middle. Above
    /// a bottom dock it takes its natural width.
    var truncates: Bool

    var body: some View {
        if let title {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 11)
                .frame(height: DockRowMetrics.labelHeight)
                .background { DockLabelBackground() }
                .fixedSize(horizontal: !truncates, vertical: true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct DockLabelBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }
}

/// Material behind the dock. Liquid Glass on macOS 26+, frosted elsewhere.
struct DockMaterialBackground: View {
    let material: DockSettings.Material
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch material {
        case .glass:
            if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                frosted(shape)
            }
        case .frosted:
            frosted(shape)
        case .solid:
            shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        }
    }

    private func frosted(_ shape: RoundedRectangle) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(.black.opacity(0.12)))
    }
}
