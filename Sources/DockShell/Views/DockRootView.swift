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
            .padding(.top, DockController.hoverHeadroom)
            .padding(.horizontal, 24) // room for the shadow and hover-scale overflow
            .padding(.bottom, 4)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                controller.contentSizeChanged(size)
            }
            .environment(\.dockIconSize, store.settings.iconSize)
            .environment(\.dockIsVisible, shellState.isVisible)
            .onChange(of: store.settings.autoHide) { _, enabled in
                controller.autoHideSettingChanged(enabled)
            }
            .onChange(of: shellState.interactionDepth) { old, new in
                if old > 0, new == 0 { controller.interactionEnded() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// The visible dock: material background plus the row of items.
struct DockSurfaceView: View {
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(RunningAppsMonitor.self) private var running
    @Environment(DockShellState.self) private var shellState

    private var cornerRadius: CGFloat { max(16, store.settings.iconSize * 0.42) }

    var body: some View {
        HStack(alignment: .bottom, spacing: itemSpacing) {
            ForEach(store.items) { item in
                DockItemView(item: item, controller: controller)
            }
            if store.settings.showRunningApps {
                unpinnedRunningApps
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            DockMaterialBackground(material: store.settings.material, cornerRadius: cornerRadius)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        // The glass fill isn't hit-testable on its own; make the whole surface a target
        // so right-click and drops land on the padding, not just on items.
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contextMenu { DockBackgroundMenu(controller: controller) }
        .dropDestination(for: URL.self) { urls, _ in
            controller.handleDroppedURLs(urls)
        } isTargeted: { targeted in
            if targeted { controller.cancelScheduledHide() }
        }
    }

    private var itemSpacing: CGFloat { max(6, store.settings.iconSize * 0.14) }

    /// Running GUI apps that aren't pinned, after a divider (like Apple's Dock).
    @ViewBuilder
    private var unpinnedRunningApps: some View {
        let pinnedIDs = Set(store.items.compactMap { $0.appItem?.bundleIdentifier })
        let pinnedPaths = Set(store.items.compactMap { $0.appItem?.url.normalizedPath })
        let extras = running.snapshot.regularApps.filter { app in
            guard let url = app.bundleURL else { return false }
            if let id = app.bundleIdentifier, pinnedIDs.contains(id) { return false }
            if pinnedPaths.contains(url.normalizedPath) { return false }
            return app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        if !extras.isEmpty {
            DockDivider()
            ForEach(extras) { app in
                if let url = app.bundleURL {
                    // Ephemeral item: stable ID derived from the pid so hover state works.
                    let item = DockItem(
                        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", abs(Int(app.processIdentifier)))) ?? UUID(),
                        kind: .app(AppItem(url: url, bundleIdentifier: app.bundleIdentifier))
                    )
                    AppItemView(item: item, app: item.appItem!, controller: controller, isPinned: false)
                }
            }
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
