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
    @Environment(\.dockEdge) private var edge

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
            AppItemView(app: app, rowID: .pinned(item.id), controller: controller)
        case let .folder(folder):
            FolderItemView(item: item, folder: folder, controller: controller)
        case let .spacer(spacer):
            SpacerItemView(item: item, spacer: spacer, controller: controller)
        case let .widget(instance):
            WidgetItemView(item: item, instance: instance, controller: controller)
        case .divider:
            DividerItemView(item: item, controller: controller)
        case .trash:
            // Never reached: the Trash isn't among `store.items`, and `TrashItemView` draws it
            // at the end of the row.
            EmptyView()
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
            let size = edge.axis.size(length: 2, thickness: iconSize * 0.8)
            Capsule()
                .fill(.secondary)
                .frame(width: size.width, height: size.height)
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

/// An icon with its running indicator (or the room for one) on the screen-edge side of it:
/// under it on the bottom edge, beside it on a side, as in Apple's Dock.
struct DockBaselineStack<Icon: View, Indicator: View>: View {
    @Environment(\.dockEdge) private var edge

    private let icon: Icon
    private let indicator: Indicator

    init(@ViewBuilder icon: () -> Icon, @ViewBuilder indicator: () -> Indicator) {
        self.icon = icon()
        self.indicator = indicator()
    }

    var body: some View {
        switch edge {
        case .bottom:
            VStack(spacing: 2) {
                icon
                indicator
            }
        case .left:
            HStack(spacing: 2) {
                indicator
                icon
            }
        case .right:
            HStack(spacing: 2) {
                icon
                indicator
            }
        }
    }
}

// MARK: - App

struct AppItemView: View {
    let app: AppItem
    /// Which row item this is: a pinned app, a running app, or a recent app.
    let rowID: DockRowItemID
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(RunningAppsMonitor.self) private var running
    @Environment(DockBadgeMonitor.self) private var badges
    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize

    private var isRunning: Bool { running.isRunning(bundleIdentifier: app.bundleIdentifier, bundleURL: app.url) }
    private var exists: Bool { FileManager.default.fileExists(atPath: app.url.path) }

    var body: some View {
        let badge = badges.label(for: app)
        DockBaselineStack {
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
                .dockBadge(badge)
                .launchBounce(shellState.launchBounces.bounce(for: app))
        } indicator: {
            runningIndicator
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.appClicked(app)
        }
        .accessibilityLabel(app.displayName)
        // Right-clicks open the menu through the controller (see `installContextClickMonitor`).
        .accessibilityAction(.showMenu) {
            controller.showAppMenu(for: app, id: rowID)
        }
        .accessibilityValue(badge ?? "")
    }

    @ViewBuilder
    private var runningIndicator: some View {
        Circle()
            .fill(.primary.opacity(0.75))
            .frame(width: 4, height: 4)
            .opacity(store.settings.showRunningIndicators && isRunning ? 1 : 0)
    }
}

// MARK: - Folder

/// Clicking opens the folder in Finder. Clicking and holding, or Browse in its menu, shows
/// its contents in a popover instead.
struct FolderItemView: View {
    let item: DockItem
    let folder: FolderItem
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(DockShellState.self) private var shellState
    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    @State private var showingContents = false
    /// Notices items landing in the folder, which hops the icon once (see `FolderArrivals`).
    @State private var watcher: FolderWatcher?
    @State private var arrivals = FolderArrivals()
    @State private var arrivalHop: LaunchBounce?
    @State private var arrivalHopTask: Task<Void, Never>?

    private static let holdDuration = 0.4

    var body: some View {
        DockBaselineStack {
            Image(nsImage: AppIconProvider.shared.icon(for: folder.url))
                .dockIcon(restingSize: iconSize)
                .launchBounce(arrivalHop)
        } indicator: {
            Color.clear.frame(width: 4, height: 4) // keep baseline aligned with apps
        }
        .contentShape(Rectangle())
        .onAppear(perform: watchForArrivals)
        .onDisappear(perform: stopWatchingForArrivals)
        .onChange(of: folder.url) {
            stopWatchingForArrivals()
            watchForArrivals()
        }
        .gesture(
            // Exclusive, so letting go after the hold doesn't count as a click as well.
            LongPressGesture(minimumDuration: Self.holdDuration)
                .exclusively(before: TapGesture())
                .onEnded { gesture in
                    switch gesture {
                    case .first: browse()
                    case .second: AppLauncher.open(folder)
                    }
                }
        )
        .popover(isPresented: $showingContents, arrowEdge: edge.popoverArrowEdge) {
            FolderBrowserView(folder: folder, sortOrderChanged: setSortOrder) { showingContents = false }
        }
        .onChange(of: showingContents) { _, shown in
            if shown { shellState.beginInteraction() } else { shellState.endInteraction() }
        }
        .onChange(of: shellState.popoverRequest) { _, request in
            // Space, while the keyboard controls the dock.
            if request?.item == item.id { browse() }
        }
        .onDisappear {
            // Switching profiles can take the folder away with its popover still open.
            if showingContents { shellState.endInteraction() }
        }
        .accessibilityLabel(folder.displayName)
        .accessibilityAction(named: "Browse") { browse() }
        .contextMenu {
            Text(folder.displayName)
            Divider()
            if FolderListing.isBrowsable(folder.url) {
                Button("Browse") { showingContents = true }
            }
            Button("Open") { AppLauncher.open(folder) }
            Button("Show in Finder") { AppLauncher.revealInFinder(folder.url) }
            Divider()
            Button("Remove from Dock", role: .destructive) { store.remove(id: item.id) }
        }
    }

    /// Files pinned to the dock have no contents to show, so they just open.
    private func browse() {
        if FolderListing.isBrowsable(folder.url) {
            showingContents = true
        } else {
            AppLauncher.open(folder)
        }
    }

    private func setSortOrder(_ order: FolderSortOrder) {
        var updated = folder
        updated.sortOrder = order
        var copy = item
        copy.kind = .folder(updated)
        store.updateItem(copy)
    }

    // MARK: Arrivals

    /// Watches the folder so the icon can hop when something lands in it, as Apple's Dock
    /// bounces Downloads. Only how many entries the folder has is read (from the folder's
    /// own metadata), never what they are: listing Downloads, Desktop, or Documents would
    /// ask the user for access to it, and the dock shouldn't do that on its own.
    private func watchForArrivals() {
        guard watcher == nil, FolderListing.isBrowsable(folder.url) else { return }
        arrivals = FolderArrivals()
        if let count = entryCount { _ = arrivals.update(count: count, at: .now) }
        watcher = FolderWatcher(url: folder.url) { folderChanged() }
    }

    private func stopWatchingForArrivals() {
        watcher?.stop()
        watcher = nil
        arrivalHopTask?.cancel()
        arrivalHopTask = nil
        arrivalHop = nil
    }

    private func folderChanged() {
        guard let count = entryCount, arrivals.update(count: count, at: .now) else { return }
        // One hop: a launch bounce whose launch ended as it started.
        arrivalHop = LaunchBounce(start: .now, launchEnd: .now)
        arrivalHopTask?.cancel()
        arrivalHopTask = Task {
            try? await Task.sleep(for: .seconds(LaunchBounce.hopDuration))
            guard !Task.isCancelled else { return }
            arrivalHop = nil
        }
    }

    /// How many entries the folder has. On APFS and HFS+ a directory's link count is its
    /// number of entries plus two, and reading it needs no access to the folder's contents.
    private var entryCount: Int? {
        (try? FileManager.default.attributesOfItem(atPath: folder.url.path))?[.referenceCount] as? Int
    }
}

// MARK: - Spacer

struct SpacerItemView: View {
    let item: DockItem
    let spacer: SpacerItem
    let controller: DockController

    @Environment(DockStore.self) private var store
    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        // An icon thick, and its ideal length along the dock, stretching to fill its slot
        // when magnified.
        let length = spacer.size == .small ? iconSize * 0.3 : iconSize * 0.7
        let vertical = edge.isVertical
        Color.clear
            .frame(
                minWidth: vertical ? iconSize : 0,
                idealWidth: vertical ? iconSize : length,
                maxWidth: vertical ? iconSize : .infinity,
                minHeight: vertical ? 0 : iconSize,
                idealHeight: vertical ? length : iconSize,
                maxHeight: vertical ? .infinity : iconSize
            )
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
                DockBackgroundMenu(controller: controller, anchor: item.id)
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
    @Environment(\.dockEdge) private var edge

    @State private var showingPopout = false
    /// How far the dock has magnified the tile, read back from the size it lays it out at.
    @State private var scale = 1.0

    private var hasPopout: Bool { registry.popout(for: instance) != nil }

    private var updater: WidgetSettingsUpdater {
        WidgetSettingsUpdater(id: item.id) { [store, item] updated in
            var copy = item
            copy.kind = .widget(updated)
            store.updateItem(copy)
        }
    }

    var body: some View {
        // Magnified tiles are laid out again at the larger icon size rather than scaled
        // up, so their text and symbols are drawn sharp at every size.
        WidgetMagnifier(scale: scale, anchor: edge.unitPoint) {
            registry.view(for: instance)
                .environment(\.dockIconSize, iconSize * scale)
                .environment(\.dockWidgetScale, scale)
                .environment(\.widgetUpdateSettings, updater)
        }
        .onGeometryChange(for: Double.self) { [iconSize, axis = edge.axis] proxy in
            // Tiles are an icon thick across the dock; that's what magnification grows.
            DockMagnification.tileScale(height: axis.thickness(of: proxy.size), iconSize: iconSize)
        } action: { newScale in
            // Follow the layout frame by frame. Animating this as well would leave the
            // content trailing its tile.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { scale = newScale }
        }
        .padding(edge.facingSide, 6) // keep baseline aligned with apps
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasPopout else { return }
            showingPopout.toggle()
        }
        .popover(isPresented: $showingPopout, arrowEdge: edge.popoverArrowEdge) {
            if let popout = registry.popout(for: instance) {
                popout.environment(\.widgetUpdateSettings, updater)
            }
        }
        .onChange(of: showingPopout) { _, shown in
            if shown { shellState.beginInteraction() } else { shellState.endInteraction() }
        }
        .onChange(of: shellState.popoverRequest) { _, request in
            // Space, while the keyboard controls the dock.
            if request?.item == item.id, hasPopout { showingPopout = true }
        }
        .onDisappear {
            // Switching profiles can take the tile away with its popover still open.
            if showingPopout { shellState.endInteraction() }
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

/// Takes the size the dock proposes, but reports the tile's resting size when measured, so
/// magnifying a tile never changes the row the dock measures. The tile is drawn at its own
/// natural size (laid out at `scale`), centered on the baseline, never stretched.
nonisolated struct WidgetMagnifier: Layout {
    var scale: Double
    /// The side of the tile on the dock's baseline (see `DockSettings.Edge.unitPoint`).
    var anchor: UnitPoint

    func makeCache(subviews: Subviews) -> DockMagnification.RestingSizeTracker {
        DockMagnification.RestingSizeTracker()
    }

    /// The tracker must outlive scale changes: while magnified, it's the only record of the
    /// resting size.
    func updateCache(_ cache: inout DockMagnification.RestingSizeTracker, subviews: Subviews) {}

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout DockMagnification.RestingSizeTracker
    ) -> CGSize {
        let natural = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        let resting = cache.update(natural: natural, scale: scale)
        return CGSize(
            width: Self.length(proposal.width, or: resting.width),
            height: Self.length(proposal.height, or: resting.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout DockMagnification.RestingSizeTracker
    ) {
        let point = CGPoint(x: bounds.minX + bounds.width * anchor.x, y: bounds.minY + bounds.height * anchor.y)
        for subview in subviews {
            subview.place(at: point, anchor: anchor, proposal: .unspecified)
        }
    }

    private static func length(_ proposed: CGFloat?, or resting: CGFloat) -> CGFloat {
        guard let proposed, proposed.isFinite else { return resting }
        return proposed
    }
}
