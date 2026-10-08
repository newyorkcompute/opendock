import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices
import os

/// Owns the dock window: creates it, keeps it sized to its content, pins it to the
/// screen edge, and runs the auto-hide state machine.
///
/// Usage from the app:
/// ```swift
/// let controller = DockController(
///     store: store, registry: registry, running: running, windows: windows, badges: badges,
///     actions: actions)
/// controller.start()
/// ```
@MainActor
public final class DockController {
    public let store: DockStore
    public let registry: WidgetRegistry
    public let running: RunningAppsMonitor
    /// Windows for app menus and click-to-minimize.
    public let windows: AppWindowManager
    public let badges: DockBadgeMonitor
    public let shellState = DockShellState()
    public var actions: DockActions

    private(set) var panel: DockPanel?
    private(set) var hostingView: NSView?
    private var contentSize: CGSize = .zero

    /// The screen the dock is on. Resolved from the display setting by `updateScreen`
    /// whenever displays or the setting change, rather than on every pointer move.
    private(set) var targetScreen: NSScreen?
    private var screenObservers: [any NSObjectProtocol] = []
    private var workspaceObservers: [any NSObjectProtocol] = []
    /// While the dock follows the active display: notices focus moving to a window on
    /// another display, which doesn't activate a different app.
    private var activeDisplayMonitor: Any?
    /// Re-checks the screen once a burst of display changes (wake, hot-plug) has settled.
    private var settleTask: Task<Void, Never>?
    private var menuObservers: [any NSObjectProtocol] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    /// Watches the pointer while it's over the dock, to notice it leaving through a
    /// transparent part of the window (where the window itself gets no events).
    var hoverMonitor: Any?
    /// Watches right-clicks and control-clicks on the dock (see `installContextClickMonitor`).
    var contextClickMonitor: Any?
    private var hideTask: Task<Void, Never>?
    /// Times the pointer resting at the edge of a full-screen Space, which reveals the dock
    /// there (see `DockController+FullScreen.swift`).
    var edgeHold = EdgeHold()
    var edgeHoldTask: Task<Void, Never>?
    /// True while the panel has joined a full-screen Space to show the dock over it.
    var isRevealedOverFullScreen = false
    var spaceObserver: (any NSObjectProtocol)?
    private var trackingProxy: TrackingProxy?
    /// Set by `revealAndHold()`; cleared when the pointer enters the dock.
    var holdUntilPointerEnters = false
    /// Watches scrolling on the dock, which can switch profiles (see `ProfileScrollGesture`).
    var scrollMonitor: Any?
    var profileScrollGesture = ProfileScrollGesture()
    /// While a profile switch animates, the window stays at least this big, so the outgoing
    /// row isn't cut off when the new one is narrower.
    private var frameHold: CGSize?
    private var frameHoldTask: Task<Void, Never>?
    var profileBannerTask: Task<Void, Never>?
    /// Tells when apps launched from the dock are up, so their icons stop bouncing.
    let launchMonitor = AppLaunchMonitor()
    /// Tells which app the user switched to, for the recent apps section.
    let activationMonitor = AppActivationMonitor()
    /// Clears the next bounce to finish, once it has landed.
    var launchBounceTask: Task<Void, Never>?
    /// The keyboard's selection while it controls the dock (see `DockController+Keyboard`).
    var keyboard = DockKeyboardNavigation<DockRowItemID>()
    /// Key presses, and the clicks that end keyboard control. Installed only while it's on.
    var keyboardMonitors: [Any] = []
    var keyboardObservers: [any NSObjectProtocol] = []
    var popoverRequestSerial = 0

    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "DockController")

    public init(
        store: DockStore,
        registry: WidgetRegistry,
        running: RunningAppsMonitor,
        windows: AppWindowManager,
        badges: DockBadgeMonitor,
        actions: DockActions = .noop
    ) {
        self.store = store
        self.registry = registry
        self.running = running
        self.windows = windows
        self.badges = badges
        self.actions = actions
    }

    // MARK: - Lifecycle

    public func start() {
        guard panel == nil else { return }

        let panel = DockPanel()
        let root = DockRootView(controller: self)
            .environment(store)
            .environment(registry)
            .environment(running)
            .environment(badges)
            .environment(shellState)
        let hosting = DockHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.dropHandler = self
        hosting.registerForDraggedTypes([.fileURL, .string])
        panel.contentView = hosting

        self.panel = panel
        hostingView = hosting

        installTrackingArea()
        targetScreen = resolveScreen()
        observeScreens()
        updateActiveDisplayMonitor()
        observeMenus()

        // Initial frame is placed once SwiftUI reports its size (see contentSizeChanged).
        if store.settings.autoHide {
            shellState.isVisible = false
        } else {
            panel.orderFrontRegardless()
        }
        updateEdgeMonitors()
        observeSpaces()

        installContextClickMonitor()
        installScrollMonitor()
        launchMonitor.onLaunchEnded = { [weak self] app in self?.launchEnded(app) }
    }

    public func stop() {
        hideTask?.cancel()
        edgeHoldTask?.cancel()
        settleTask?.cancel()
        frameHoldTask?.cancel()
        profileBannerTask?.cancel()
        launchBounceTask?.cancel()
        launchMonitor.onLaunchEnded = nil
        activationMonitor.onActivate = nil
        badges.isDockVisible = false
        _ = keyboard.end()
        shellState.keyboardSelection = nil
        removeKeyboardMonitors()
        removeScrollMonitor()
        removeEdgeMonitors()
        removeHoverMonitor()
        screenObservers.forEach(NotificationCenter.default.removeObserver)
        screenObservers = []
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        if let activeDisplayMonitor { NSEvent.removeMonitor(activeDisplayMonitor) }
        activeDisplayMonitor = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        removeContextClickMonitor()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Geometry

    /// Called by the root view whenever its natural size changes.
    func contentSizeChanged(_ size: CGSize) {
        guard size != contentSize, size.width > 0, size.height > 0 else { return }
        contentSize = size
        applyFrame(animated: false)
    }

    /// Keep the window from shrinking for `duration`, then fit it to the content again.
    func holdFrameSize(for duration: Duration) {
        let held = frameHold ?? contentSize
        frameHold = CGSize(width: max(held.width, contentSize.width), height: max(held.height, contentSize.height))
        frameHoldTask?.cancel()
        frameHoldTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled else { return }
            frameHold = nil
            applyFrame(animated: false)
        }
    }

    private var frameSize: CGSize {
        guard let frameHold else { return contentSize }
        return CGSize(width: max(frameHold.width, contentSize.width), height: max(frameHold.height, contentSize.height))
    }

    /// The screen edge the dock is on.
    var edge: DockSettings.Edge { store.settings.edge }

    /// Frame for the panel when fully shown. The window reaches the screen edge so the
    /// strip between it and the dock still counts as "over the dock"; the layout insets
    /// the surface.
    private func shownFrame(on screen: NSScreen) -> NSRect {
        DockPlacement.shownFrame(contentSize: frameSize, visibleFrame: screen.visibleFrame, edge: edge)
    }

    /// Frame for the panel when hidden: just past the dock's edge of the screen.
    private func hiddenFrame(on screen: NSScreen) -> NSRect {
        DockPlacement.hiddenFrame(contentSize: frameSize, on: screen.placementScreen, edge: edge)
    }

    func applyFrame(animated: Bool) {
        guard let panel, let screen = targetScreen else { return }
        let frame = shellState.isVisible ? shownFrame(on: screen) : hiddenFrame(on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Displays

    /// The screen the display setting picks right now.
    private func resolveScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let activeIndex = NSScreen.main.flatMap { main in screens.firstIndex { $0 == main } }
        let index = DockPlacement.screenIndex(
            for: store.settings.display,
            in: screens.map(\.placementScreen),
            activeIndex: activeIndex
        )
        return index.map { screens[$0] }
    }

    /// Re-resolve the dock's screen and move the dock there. With `force` false the
    /// frame is only reapplied if the screen changed, so frequent checks (clicks, app
    /// switches) don't disturb a running slide animation.
    private func updateScreen(force: Bool) {
        guard panel != nil else { return }
        let old = targetScreen
        let new = resolveScreen()
        targetScreen = new
        let moved = old?.frame != new?.frame || old?.visibleFrame != new?.visibleFrame
        guard moved || force else { return }
        if moved {
            log.debug(
                "dock screen: \(new?.localizedName ?? "none", privacy: .public) \(String(describing: new?.frame), privacy: .public)"
            )
            // Hover state refers to where the dock used to be.
            resetMagnification()
        }
        applyFrame(animated: false)
        if moved, shellState.isVisible, store.settings.autoHide {
            scheduleHide()
        }
    }

    /// Update now, and again once things settle: after wake or hot-plug the display list
    /// and visible frames can arrive in several steps.
    private func screensMayHaveChanged(force: Bool) {
        updateScreen(force: force)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.updateScreen(force: force)
        }
    }

    /// Called by the root view's `onChange(of: settings.display)`.
    func displaySettingChanged() {
        updateActiveDisplayMonitor()
        updateScreen(force: true)
    }

    /// Called by the root view's `onChange(of: settings.edge)`. The layout turns to run
    /// along the new edge and reports its new size, which places the window there; this
    /// moves it right away in case the size happens not to change, and drops hover state
    /// that refers to the old edge.
    func edgeSettingChanged() {
        resetMagnification()
        applyFrame(animated: false)
    }

    private func observeScreens() {
        // Resolution, arrangement, main display, and displays being added or removed.
        screenObservers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensMayHaveChanged(force: true) }
            }
        ]

        let workspace = NSWorkspace.shared.notificationCenter
        let forced: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        // These move the active menu bar to another display.
        let focus: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        workspaceObservers =
            forced.map { name in
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screensMayHaveChanged(force: true) }
                }
            }
            + focus.map { name in
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.store.settings.display == .active else { return }
                        self.screensMayHaveChanged(force: false)
                    }
                }
            }
    }

    private func updateActiveDisplayMonitor() {
        let wanted = store.settings.display == .active
        if wanted, activeDisplayMonitor == nil {
            let handler: @Sendable (NSEvent) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.screensMayHaveChanged(force: false) }
            }
            activeDisplayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: handler)
        } else if !wanted, let monitor = activeDisplayMonitor {
            NSEvent.removeMonitor(monitor)
            activeDisplayMonitor = nil
        }
    }

    /// An open menu (an item's context menu, or the menu bar menu) counts as an
    /// interaction: the dock holds its magnification and stays up until it closes, and
    /// the label gets out of the menu's way, as in Apple's Dock.
    private func observeMenus() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.shellState.hoveredItemID = nil
                    self?.shellState.beginInteraction()
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shellState.endInteraction() }
            },
        ]
    }

    // MARK: - Auto-hide

    /// Called by the root view's `onChange(of: settings.autoHide)`.
    func autoHideSettingChanged(_ enabled: Bool) {
        endFullScreenReveal()
        updateEdgeMonitors()
        if enabled {
            scheduleHide()
        } else {
            hideTask?.cancel()
            reveal()
        }
    }

    /// With auto-hide on, hiding is the normal state. Revealed over a full-screen Space, the
    /// dock hides the same way when the pointer leaves, whatever the setting.
    var hidesWhenPointerLeaves: Bool { store.settings.autoHide || isRevealedOverFullScreen }

    public var isVisible: Bool { shellState.isVisible }

    /// Slide the dock on screen.
    public func reveal() {
        guard let panel, let screen = targetScreen else { return }
        hideTask?.cancel()
        guard !shellState.isVisible else { return }
        panel.setFrame(hiddenFrame(on: screen), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        shellState.isVisible = true
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(shownFrame(on: screen), display: true)
                panel.animator().alphaValue = 1
            },
            completionHandler: {
                // The dock slid in under a pointer that may not move again for a while
                // (it's resting on the edge that revealed it); magnify without waiting.
                MainActor.assumeIsolated {
                    guard self.shellState.isVisible else { return }
                    self.pointerMoved(to: self.layoutPoint(fromScreen: NSEvent.mouseLocation))
                }
            })
    }

    /// Reveal and keep the dock on screen until the pointer has entered it once.
    /// Used by explicit "Show Dock" commands, where hiding again after the delay
    /// (because the pointer happens to be elsewhere) would feel broken.
    public func revealAndHold() {
        holdUntilPointerEnters = true
        reveal()
    }

    /// Slide the dock off screen (with auto-hide on, or while revealed over a full-screen Space).
    public func hide() {
        holdUntilPointerEnters = false
        guard let panel, let screen = targetScreen, shellState.isVisible else { return }
        // A reorder dragged off the dock may still come back; it's held up until it ends.
        guard !shellState.isInteracting, shellState.draggingItemID == nil else { return }
        shellState.isVisible = false
        resetMagnification()
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(self.hiddenFrame(on: screen), display: true)
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                MainActor.assumeIsolated {
                    guard !self.shellState.isVisible else { return }
                    panel.orderOut(nil)
                    self.endFullScreenReveal()
                }
            })
    }

    /// Start the countdown to hide, after the auto-hide delay unless `delay` (in seconds)
    /// says otherwise. Cancelled if the pointer comes back. Not while the keyboard is in
    /// control: the dock stays up until that ends.
    func scheduleHide(after delay: Double? = nil) {
        guard hidesWhenPointerLeaves, !holdUntilPointerEnters, !keyboard.isActive else { return }
        hideTask?.cancel()
        let delay = delay ?? store.settings.autoHideDelay
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if pointerIsOverDock {
                scheduleHide()
                return
            }
            hide()
        }
    }

    func cancelScheduledHide() {
        hideTask?.cancel()
    }

    /// Called when an interaction (popover/menu) ends; re-arm hiding if the pointer left.
    func interactionEnded() {
        if keyboard.isActive {
            // The popover or menu took the keyboard; the selection takes it back.
            keyboardInteractionEnded()
            return
        }
        guard !pointerIsOverDock else {
            // Hover events stopped while the menu or popover was open; pick up from here.
            pointerMoved(to: layoutPoint(fromScreen: NSEvent.mouseLocation))
            return
        }
        pointerLeftDock()
        scheduleHide()
    }

    /// True when the pointer is over the dock *or* in the strip between the dock and
    /// the screen edge. Without the strip, a pointer resting on the very edge of the
    /// screen (where it revealed the dock) would count as "outside" and hide it again.
    var pointerIsOverDock: Bool {
        guard let panel, panel.isVisible, let screen = targetScreen else { return false }
        // The window is larger than the dock (room for magnification), so use the
        // dock's own hit zone once the layout has produced one.
        let zone = (hitZoneOnScreen ?? panel.frame).insetBy(dx: -4, dy: -4)
        return DockPlacement.reachingScreenEdge(zone, of: screen.frame, edge: edge).contains(NSEvent.mouseLocation)
    }

    /// The pointer is watched everywhere while there's an edge that can reveal the dock.
    func updateEdgeMonitors() {
        if store.settings.autoHide || store.settings.revealInFullScreen {
            if globalMouseMonitor == nil { installEdgeMonitors() }
        } else {
            removeEdgeMonitors()
        }
    }

    private func installEdgeMonitors() {
        removeEdgeMonitors()
        log.debug("installing edge monitors")
        let handler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
    }

    private func removeEdgeMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func pointerMoved() {
        guard let screen = targetScreen else { return }
        let location = NSEvent.mouseLocation
        if shellState.isVisible, hidesWhenPointerLeaves {
            if !pointerIsOverDock, hideTask == nil || hideTask?.isCancelled == true {
                scheduleHide()
            }
            return
        }
        // Hidden, or shown without auto-hide (which a full-screen Space doesn't display):
        // the dock's edge of its screen reveals it. On a full-screen Space the pointer has
        // to stay there a moment; elsewhere only an auto-hidden dock has anything to show.
        let atEdge = DockPlacement.isAtRevealEdge(location, of: screen.frame, edge: edge)
        if atEdge, store.settings.revealInFullScreen, isOnFullScreenSpace {
            edgeHoldChanged(atEdge: true)
        } else {
            edgeHoldChanged(atEdge: false)
            if atEdge, store.settings.autoHide { reveal() }
        }
    }

    // MARK: - Tracking

    private func installTrackingArea() {
        guard let hostingView else { return }
        let proxy = TrackingProxy(controller: self)
        trackingProxy = proxy // NSTrackingArea does not retain its owner
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: proxy,
            userInfo: nil
        )
        hostingView.addTrackingArea(area)
    }

    /// NSTrackingArea wants a responder as owner; this forwards to the controller.
    private final class TrackingProxy: NSResponder {
        unowned let controller: DockController
        init(controller: DockController) {
            self.controller = controller
            super.init()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func mouseEntered(with event: NSEvent) {
            MainActor.assumeIsolated {
                guard controller.pointerIsOverDock else { return }
                controller.holdUntilPointerEnters = false
                controller.cancelScheduledHide()
            }
        }

        override func mouseExited(with event: NSEvent) {
            MainActor.assumeIsolated { controller.scheduleHide() }
        }
    }

    // MARK: - Panel presentation helpers

    /// Activates the app briefly so standard panels (open/save) can take focus.
    func presentingSystemPanel<T>(_ body: () -> T) -> T {
        shellState.beginInteraction()
        NSApp.activate()
        defer {
            shellState.endInteraction()
            interactionEnded()
        }
        return body()
    }
}
