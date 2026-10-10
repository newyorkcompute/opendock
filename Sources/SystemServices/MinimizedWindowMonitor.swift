import AppKit
import DockCore
import Observation

/// Where minimized windows come from. `SystemMinimizedWindowService` in production talks
/// to the Accessibility API; tests use a stand-in. Nothing here should run unless
/// Accessibility access is already granted — `MinimizedWindowMonitor` is what enforces that.
@MainActor
public protocol MinimizedWindowSource: AnyObject {
    /// The minimized windows last read. Empty until `start` has delivered an update.
    var windows: [MinimizedDockWindow] { get }
    /// Begins delivering `onChange` as windows are minimized, restored, closed, or renamed.
    /// The first call is how the current windows arrive; there is no timer behind it.
    func start(_ onChange: @escaping @MainActor () -> Void)
    /// Stops delivering updates and forgets the windows it was holding.
    func stop()
    /// Unminimizes `window` and brings its app forward.
    func restore(_ window: MinimizedDockWindow)
    /// Closes `window`.
    func close(_ window: MinimizedDockWindow)
}

/// The minimized windows to show at the end of the dock, and their thumbnails.
///
/// While "Show minimized windows" is off, or Accessibility access isn't granted, this
/// holds nothing and asks nothing of the system: no window query, no observer. With both,
/// it follows Accessibility notifications (see `MinimizedWindowSource`) and keeps the row
/// in `MinimizedWindowSection`'s order. Thumbnails are captured only when Screen Recording
/// is already granted, and never cause a prompt.
@MainActor
@Observable
public final class MinimizedWindowMonitor {
    /// The windows the dock shows, in dock order. Empty when the section is off or
    /// Accessibility access isn't granted.
    public private(set) var windows: [MinimizedDockWindow] = []

    /// The Accessibility permission the windows come through, shared with everything else
    /// that needs it.
    public let accessibility: AccessibilityPermission
    /// Screen Recording, for thumbnails. Never requested from here.
    public let screenRecording: ScreenRecordingPermission

    @ObservationIgnored private let source: any MinimizedWindowSource
    @ObservationIgnored private let capturer: any WindowThumbnailCapturing
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var captureGeneration = 0
    /// Observed, so a thumbnail that arrives after the window is already on the dock
    /// redraws the item. Assigned as a whole, never mutated in place.
    private var thumbnails: [Int: NSImage] = [:]

    public init(
        accessibility: AccessibilityPermission,
        screenRecording: ScreenRecordingPermission,
        source: any MinimizedWindowSource = SystemMinimizedWindowService(),
        thumbnails capturer: any WindowThumbnailCapturing = SystemWindowThumbnailCapturer()
    ) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.source = source
        self.capturer = capturer
    }

    isolated deinit {
        source.stop()
    }

    /// The thumbnail for a window, when Screen Recording was granted and a capture succeeded.
    public func thumbnail(for id: MinimizedDockWindow.ID) -> NSImage? {
        thumbnails[id.windowID]
    }

    /// The setting changed. Off tears everything down; on starts only if access is granted.
    public func setEnabled(_ enabled: Bool) {
        wantsRunning = enabled
        apply()
    }

    /// The app came forward, or Settings may have just changed a permission. Starts or
    /// stops to match, and picks up thumbnails if Screen Recording is now granted.
    public func noteAppBecameActive() {
        _ = accessibility.refresh()
        _ = screenRecording.refresh()
        apply()
    }

    /// Screen Recording may have just been granted or taken away. Does not prompt.
    public func refreshThumbnails() {
        _ = screenRecording.refresh()
        updateThumbnails()
    }

    /// Stops observers and drops the windows. The setting itself is unchanged; the next
    /// `setEnabled(true)` starts again.
    public func stop() {
        wantsRunning = false
        apply()
    }

    /// Restores `window`: unminimized, and its app brought forward. Does nothing without
    /// Accessibility access.
    public func restore(_ window: MinimizedDockWindow) {
        guard accessibility.refresh() else { return }
        source.restore(window)
    }

    /// Closes `window`. Does nothing without Accessibility access.
    public func close(_ window: MinimizedDockWindow) {
        guard accessibility.refresh() else { return }
        source.close(window)
    }

    // MARK: - Running

    private func apply() {
        guard wantsRunning, accessibility.refresh() else {
            stopObserving()
            return
        }
        if !observing {
            observing = true
            source.start { [weak self] in self?.reload() }
        }
        reload()
    }

    private func stopObserving() {
        if observing {
            source.stop()
            observing = false
        }
        captureGeneration += 1
        if !windows.isEmpty { windows = [] }
        if !thumbnails.isEmpty { thumbnails = [:] }
    }

    private func reload() {
        guard wantsRunning, accessibility.refresh() else {
            stopObserving()
            return
        }
        let next = MinimizedWindowSection.displayed(
            reported: source.windows,
            previouslyShown: windows,
            showMinimizedWindows: true
        )
        if next != windows { windows = next }
        updateThumbnails()
    }

    /// Captures thumbnails for windows that don't have one yet, and drops the rest.
    /// Refuses outright when Screen Recording isn't granted, so ScreenCaptureKit is never
    /// asked to prompt.
    private func updateThumbnails() {
        guard wantsRunning, screenRecording.refresh() else {
            captureGeneration += 1
            if !thumbnails.isEmpty { thumbnails = [:] }
            return
        }
        let ids = Set(windows.map(\.id.windowID))
        let kept = thumbnails.filter { ids.contains($0.key) }
        if kept.count != thumbnails.count { thumbnails = kept }
        let missing = windows.map(\.id.windowID).filter { thumbnails[$0] == nil }
        guard !missing.isEmpty else { return }
        captureGeneration += 1
        let generation = captureGeneration
        Task { [weak self] in
            guard let self else { return }
            let images = await capturer.capture(windowIDs: missing)
            guard generation == captureGeneration else { return }
            let current = Set(windows.map(\.id.windowID))
            var next = thumbnails
            for (id, image) in images where current.contains(id) {
                next[id] = NSImage(
                    cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
            }
            thumbnails = next
        }
    }
}
