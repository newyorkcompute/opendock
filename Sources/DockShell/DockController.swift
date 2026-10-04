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
/// let controller = DockController(store: store, registry: registry, running: running, actions: actions)
/// controller.start()
/// ```
@MainActor
public final class DockController {
    public let store: DockStore
    public let registry: WidgetRegistry
    public let running: RunningAppsMonitor
    public let shellState = DockShellState()
    public var actions: DockActions

    private var panel: DockPanel?
    private var hostingView: NSView?
    private var contentSize: CGSize = .zero

    private var screenObserver: (any NSObjectProtocol)?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var trackingProxy: TrackingProxy?

    private let log = Logger(subsystem: "org.opendock", category: "DockController")

    /// Distance from the screen edge to the dock, in points.
    private let edgeMargin: CGFloat = 6
    /// Extra room above the content so hover-scaled icons don't clip.
    static let hoverHeadroom: CGFloat = 18

    public init(
        store: DockStore,
        registry: WidgetRegistry,
        running: RunningAppsMonitor,
        actions: DockActions = .noop
    ) {
        self.store = store
        self.registry = registry
        self.running = running
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
            .environment(shellState)
        let hosting = DockHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        hostingView = hosting

        installTrackingArea()
        observeScreens()

        // Initial frame is placed once SwiftUI reports its size (see contentSizeChanged).
        if store.settings.autoHide {
            shellState.isVisible = false
            installEdgeMonitors()
        } else {
            panel.orderFrontRegardless()
        }
    }

    public func stop() {
        hideTask?.cancel()
        removeEdgeMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
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

    private var targetScreen: NSScreen? {
        // The screen with the menu bar. A per-screen setting can come later.
        NSScreen.screens.first
    }

    /// Frame for the panel when fully shown.
    private func shownFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(contentSize.width, visible.width)
        let x = visible.midX - width / 2
        let y = visible.minY + edgeMargin
        return NSRect(x: x, y: y, width: width, height: contentSize.height)
    }

    /// Frame for the panel when hidden: just below the bottom edge of the screen.
    private func hiddenFrame(on screen: NSScreen) -> NSRect {
        var frame = shownFrame(on: screen)
        frame.origin.y = screen.frame.minY - frame.height - 1
        return frame
    }

    private func applyFrame(animated: Bool) {
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

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFrame(animated: false) }
        }
    }

    // MARK: - Auto-hide

    /// Called by the root view's `onChange(of: settings.autoHide)`.
    func autoHideSettingChanged(_ enabled: Bool) {
        if enabled {
            installEdgeMonitors()
            scheduleHide()
        } else {
            removeEdgeMonitors()
            hideTask?.cancel()
            reveal()
        }
    }

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
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(shownFrame(on: screen), display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Slide the dock off screen (only meaningful with auto-hide on).
    public func hide() {
        guard let panel, let screen = targetScreen, shellState.isVisible else { return }
        guard !shellState.isInteracting else { return }
        shellState.isVisible = false
        shellState.hoveredItemID = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(self.hiddenFrame(on: screen), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !self.shellState.isVisible { panel.orderOut(nil) }
            }
        })
    }

    /// Start the countdown to hide. Cancelled if the pointer comes back.
    func scheduleHide() {
        guard store.settings.autoHide else { return }
        hideTask?.cancel()
        let delay = store.settings.autoHideDelay
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if pointerIsOverDock { scheduleHide(); return }
            hide()
        }
    }

    func cancelScheduledHide() {
        hideTask?.cancel()
    }

    /// Called when an interaction (popover/menu) ends; re-arm hiding if the pointer left.
    func interactionEnded() {
        if store.settings.autoHide, !pointerIsOverDock {
            scheduleHide()
        }
    }

    private var pointerIsOverDock: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func installEdgeMonitors() {
        removeEdgeMonitors()
        let handler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler)
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
        guard store.settings.autoHide, let screen = targetScreen else { return }
        let location = NSEvent.mouseLocation
        if shellState.isVisible {
            if !pointerIsOverDock, hideTask == nil || hideTask?.isCancelled == true {
                scheduleHide()
            }
            return
        }
        // Hidden: reveal when the pointer touches the bottom edge of the dock's screen.
        let atEdge = location.y <= screen.frame.minY + 1
            && location.x >= screen.frame.minX
            && location.x <= screen.frame.maxX
        if atEdge { reveal() }
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
            MainActor.assumeIsolated { controller.cancelScheduledHide() }
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
