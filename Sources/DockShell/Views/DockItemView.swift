import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Dispatches a `DockItem` to the right view and makes it draggable for reordering
/// (drops are handled by `DockHostingView`). Magnification is done by
/// `DockMagnifyingLayout`, which proposes a larger size; item views fill it.
struct DockItemView: View {
    let item: DockItem
    let controller: DockController

    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize

    var body: some View {
        content
            .opacity(shellState.draggingItemID == item.id ? 0 : 1)
            .draggable(item.id.uuidString) {
                dragPreview
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case let .app(app):
            AppItemView(item: item, app: app, controller: controller, isPinned: true)
        case let .folder(folder):
            FolderItemView(item: item, folder: folder, controller: controller)
        case let .spacer(spacer):
            SpacerItemView(item: item, spacer: spacer, controller: controller)
        case let .widget(instance):
            WidgetItemView(item: item, instance: instance, controller: controller)
        case .divider:
            DividerItemView(item: item, controller: controller)
        }
    }

    @ViewBuilder
    private var dragPreview: some View {
        switch item.kind {
        case let .app(app):
            Image(nsImage: AppIconProvider.shared.icon(for: app.url))
                .resizable()
                .frame(width: iconSize, height: iconSize)
        case let .folder(folder):
            Image(nsImage: AppIconProvider.shared.icon(for: folder.url))
                .resizable()
                .frame(width: iconSize, height: iconSize)
        case .divider:
            Capsule()
                .fill(.secondary)
                .frame(width: 2, height: iconSize * 0.8)
        default:
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary.opacity(0.3))
                .frame(width: iconSize, height: iconSize)
        }
    }
}

extension Image {
    /// A square icon that is `restingSize` when nothing is magnified and fills
    /// whatever larger square the layout proposes when it is.
    func dockIcon(restingSize: Double) -> some View {
        resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(idealWidth: restingSize, idealHeight: restingSize)
    }
}

// MARK: - App

struct AppItemView: View {
    let item: DockItem
    let app: AppItem
    let controller: DockController
    let isPinned: Bool

    @Environment(DockStore.self) private var store
    @Environment(RunningAppsMonitor.self) private var running
    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize

    private var isRunning: Bool { running.isRunning(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url) }
    private var exists: Bool { FileManager.default.fileExists(atPath: app.url.path) }

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: AppIconProvider.shared.icon(for: app.url))
                .dockIcon(restingSize: iconSize)
                .opacity(exists ? 1 : 0.4)
                .overlay(alignment: .bottomTrailing) {
                    if !exists {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.white, .red)
                            .font(.system(size: iconSize * 0.3))
                    }
                }
            runningIndicator
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AppLauncher.open(app, running: running)
        }
        .accessibilityLabel(app.displayName)
        .contextMenu { menu }
    }

    @ViewBuilder
    private var runningIndicator: some View {
        Circle()
            .fill(.primary.opacity(0.75))
            .frame(width: 4, height: 4)
            .opacity(store.settings.showRunningIndicators && isRunning ? 1 : 0)
    }

    @ViewBuilder
    private var menu: some View {
        Text(app.displayName)
        Divider()
        if isRunning {
            Button("Hide") { AppLauncher.hide(app, running: running) }
            Button("Quit") { AppLauncher.quit(app, running: running) }
        } else {
            Button("Open") { AppLauncher.open(app, running: running) }
        }
        Button("New Window") { AppLauncher.openNewInstance(app) }
        Divider()
        Button("Show in Finder") { AppLauncher.revealInFinder(app.url) }
        Divider()
        if isPinned {
            Button("Remove from Dock", role: .destructive) { store.remove(id: item.id) }
        } else {
            Button("Keep in Dock") { store.addApp(at: app.url) }
        }
    }
}

// MARK: - Folder

struct FolderItemView: View {
    let item: DockItem
    let folder: FolderItem
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(\.dockIconSize) private var iconSize

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: AppIconProvider.shared.icon(for: folder.url))
                .dockIcon(restingSize: iconSize)
            Color.clear.frame(width: 4, height: 4) // keep baseline aligned with apps
        }
        .contentShape(Rectangle())
        .onTapGesture { AppLauncher.open(folder) }
        .accessibilityLabel(folder.displayName)
        .contextMenu {
            Text(folder.displayName)
            Divider()
            Button("Open") { AppLauncher.open(folder) }
            Button("Show in Finder") { AppLauncher.revealInFinder(folder.url) }
            Divider()
            Button("Remove from Dock", role: .destructive) { store.remove(id: item.id) }
        }
    }
}

// MARK: - Spacer

struct SpacerItemView: View {
    let item: DockItem
    let spacer: SpacerItem
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(\.dockIconSize) private var iconSize

    var body: some View {
        Color.clear
            .frame(minWidth: 0, idealWidth: spacer.size == .small ? iconSize * 0.3 : iconSize * 0.7, maxWidth: .infinity)
            .frame(height: iconSize)
            .contentShape(Rectangle())
            .contextMenu {
                Text("Spacer")
                Divider()
                Button(spacer.size == .small ? "Make Regular" : "Make Small") {
                    var updated = item
                    updated.kind = .spacer(SpacerItem(size: spacer.size == .small ? .regular : .small))
                    store.updateItem(updated)
                }
                Button("Remove from Dock", role: .destructive) { store.remove(id: item.id) }
                Divider()
                // Spacers are the easiest empty area to hit, so expose the dock menu here too.
                DockBackgroundMenu(controller: controller)
            }
    }
}

// MARK: - Widget

struct WidgetItemView: View {
    let item: DockItem
    let instance: WidgetInstance
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(WidgetRegistry.self) private var registry
    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize

    @State private var showingPopout = false

    private var hasPopout: Bool { registry.popout(for: instance) != nil }

    private var updater: WidgetSettingsUpdater {
        WidgetSettingsUpdater(id: item.id) { [store, item] updated in
            var copy = item
            copy.kind = .widget(updated)
            store.updateItem(copy)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            registry.view(for: instance)
                .environment(\.widgetUpdateSettings, updater)
            Color.clear.frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasPopout else { return }
            showingPopout.toggle()
        }
        .popover(isPresented: $showingPopout, arrowEdge: .top) {
            if let popout = registry.popout(for: instance) {
                popout.environment(\.widgetUpdateSettings, updater)
            }
        }
        .onChange(of: showingPopout) { _, shown in
            if shown { shellState.beginInteraction() } else { shellState.endInteraction() }
        }
        .accessibilityLabel(registry.displayName(for: instance))
        .contextMenu {
            Text(registry.displayName(for: instance))
            Divider()
            if hasPopout {
                Button("Open") { showingPopout = true }
            }
            Button("Duplicate") {
                if let index = store.items.firstIndex(where: { $0.id == item.id }) {
                    store.insert(.widget(instance.typeID, settings: instance.settings), at: index + 1)
                }
            }
            Divider()
            Button("Remove from Dock", role: .destructive) { store.remove(id: item.id) }
        }
    }
}
