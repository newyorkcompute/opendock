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
            .environment(\.dockIsVisible, shellState.isVisible)
            .onChange(of: store.settings.autoHide) { _, enabled in
                controller.autoHideSettingChanged(enabled)
            }
            .onChange(of: store.settings.display) {
                controller.displaySettingChanged()
            }
            .onChange(of: shellState.interactionDepth) { old, new in
                if old > 0, new == 0 { controller.interactionEnded() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// The visible dock: material background, the row of items, and the hovered item's label,
/// all placed by `DockMagnifyingLayout`.
struct DockSurfaceView: View {
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry
    @Environment(RunningAppsMonitor.self) private var running
    @Environment(DockShellState.self) private var shellState

    var body: some View {
        let metrics = DockRowMetrics(settings: store.settings)
        let extras = store.settings.showRunningApps ? unpinnedRunningApps : []
        DockMagnifyingLayout(
            metrics: metrics,
            pointerX: shellState.pointerX,
            amount: shellState.magnification,
            hoveredID: shellState.hoveredItemID,
            geometry: shellState.geometry
        ) {
            DockHitZone()
                .dockLayoutRole(.hitZone)

            surface(cornerRadius: metrics.cornerRadius)
                .dockLayoutRole(.surface)

            ForEach(store.items) { item in
                DockItemView(item: item, controller: controller)
                    .dockLayoutRole(.item(item.id, magnifies: !item.isWidget, hoverable: !item.isSpacer))
            }

            if !extras.isEmpty {
                DockDivider()
                    .dockLayoutRole(.item(nil, magnifies: false, hoverable: false))
                ForEach(extras, id: \.item.id) { extra in
                    AppItemView(item: extra.item, app: extra.app, controller: controller, isPinned: false)
                        .dockLayoutRole(.item(extra.item.id, magnifies: true, hoverable: true))
                }
            }

            DockItemLabel(title: label(for: shellState.hoveredItemID, extras: extras))
                .dockLayoutRole(.label)
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

    private func label(for id: DockItem.ID?, extras: [UnpinnedApp]) -> String? {
        guard let id else { return nil }
        if let item = store.items.first(where: { $0.id == id }) {
            switch item.kind {
            case let .app(app): return app.displayName
            case let .folder(folder): return folder.displayName
            case let .widget(instance): return registry.displayName(for: instance)
            case .spacer: return nil
            }
        }
        return extras.first { $0.item.id == id }?.app.displayName
    }

    struct UnpinnedApp {
        let item: DockItem
        let app: AppItem
    }

    /// Running GUI apps that aren't pinned, shown after a divider (like Apple's Dock).
    private var unpinnedRunningApps: [UnpinnedApp] {
        let pinnedIDs = Set(store.items.compactMap { $0.appItem?.bundleIdentifier })
        let pinnedPaths = Set(store.items.compactMap { $0.appItem?.url.normalizedPath })
        return running.snapshot.regularApps.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            if let id = app.bundleIdentifier, pinnedIDs.contains(id) { return nil }
            if pinnedPaths.contains(url.normalizedPath) { return nil }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
            let appItem = AppItem(url: url, bundleIdentifier: app.bundleIdentifier)
            // Ephemeral item: stable ID derived from the pid so hover state works.
            let item = DockItem(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", abs(Int(app.processIdentifier)))) ?? UUID(),
                kind: .app(appItem)
            )
            return UnpinnedApp(item: item, app: appItem)
        }
    }
}

/// Keeps the pointer "on the dock" between and above magnified icons. Nearly transparent
/// rather than clear: the window server lets events through fully transparent pixels.
struct DockHitZone: View {
    var body: some View {
        Rectangle().fill(.black.opacity(0.005))
    }
}

/// The item name above the hovered icon, like the Dock's labels.
struct DockItemLabel: View {
    let title: String?

    var body: some View {
        if let title {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: DockRowMetrics.labelHeight)
                .background { DockLabelBackground() }
                .fixedSize()
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

struct DockDivider: View {
    @Environment(\.dockIconSize) private var iconSize
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.primary.opacity(0.18))
            .frame(width: 1, height: iconSize * 0.8)
            .padding(.horizontal, 2)
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
