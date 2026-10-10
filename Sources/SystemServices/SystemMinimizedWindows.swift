import AppKit
import ApplicationServices
import Darwin
import DockCore
import os

/// Reads minimized windows through `AXUIElement` and follows them with Accessibility
/// notifications, so the dock isn't polling. Needs the user to allow OpenDock in
/// System Settings > Privacy & Security > Accessibility. `MinimizedWindowMonitor` does
/// not start this until that access is granted.
@MainActor
public final class SystemMinimizedWindowService: MinimizedWindowSource {
    public private(set) var windows: [MinimizedDockWindow] = []

    private struct Watched {
        var observer: AXObserver
        var windows: [Int: AXUIElement]
    }

    /// Notifications on the application: a window can be minimized before we've ever seen it.
    private static let applicationNotes = [
        kAXWindowCreatedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
        kAXUIElementDestroyedNotification,
    ]
    /// Notifications on a minimized window itself: closing one doesn't always tell the app.
    private static let windowNotes = [
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
        kAXUIElementDestroyedNotification,
    ]

    private var watched: [pid_t: Watched] = [:]
    private var elements: [pid_t: [Int: AXUIElement]] = [:]
    private var cached: [pid_t: [MinimizedDockWindow]] = [:]
    private var onChange: (@MainActor () -> Void)?
    private var workspaceTokens: [any NSObjectProtocol] = []
    private var pendingPIDs: Set<pid_t> = []
    private var pendingFull = false
    private var refreshTask: Task<Void, Never>?
    private let box = AXObservationBox()
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "MinimizedWindows")

    public init() {}

    isolated deinit {
        stop()
    }

    public func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        // An app that has stopped responding would otherwise hold the dock for the
        // default of about six seconds. Set only once we're actually going to ask.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        self.onChange = onChange
        box.onProcess = { [weak self] pid in self?.note(pid) }
        observeWorkspace()
        for app in candidates() { watch(app) }
        pendingFull = true
        schedule()
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        pendingPIDs = []
        pendingFull = false
        onChange = nil
        box.onProcess = nil
        for pid in Array(watched.keys) { unwatch(pid) }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens = []
        elements = [:]
        cached = [:]
        windows = []
    }

    public func restore(_ window: MinimizedDockWindow) {
        guard let element = elements[pid_t(window.processIdentifier)]?[window.id.windowID] else { return }
        set(kAXMinimizedAttribute, to: false, on: element)
        // Unlike `NSRunningApplication.activate`, which macOS may refuse to a background
        // app like the dock.
        set(kAXFrontmostAttribute, to: true, on: AXUIElementCreateApplication(pid_t(window.processIdentifier)))
    }

    public func close(_ window: MinimizedDockWindow) {
        guard let element = elements[pid_t(window.processIdentifier)]?[window.id.windowID] else { return }
        guard let button: AXUIElement = element.value(of: kAXCloseButtonAttribute) else {
            log.debug("Minimized window \(window.id.windowID, privacy: .public) has no close button")
            return
        }
        let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
        if error != .success {
            log.debug("Couldn't close a minimized window: AXError \(error.rawValue, privacy: .public)")
        }
    }

    // MARK: - Notifications

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let pid = Self.processIdentifier(in: note) else { return }
                MainActor.assumeIsolated { self?.applicationLaunched(pid) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                guard let pid = Self.processIdentifier(in: note) else { return }
                MainActor.assumeIsolated { self?.applicationEnded(pid) }
            },
        ]
    }

    private func applicationLaunched(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), isCandidate(app) else { return }
        watch(app)
        note(pid)
    }

    /// `publishNow` is false while a scan is about to publish the whole list itself.
    /// Publishing a pid early would drop its windows and then append them, which moves
    /// them to the end of the dock.
    private func applicationEnded(_ pid: pid_t, publishNow: Bool = true) {
        unwatch(pid)
        elements[pid] = nil
        guard cached.removeValue(forKey: pid) != nil else { return }
        if publishNow { publish() }
    }

    /// A burst of notifications (minimize, title, destroy) becomes one reread.
    private func note(_ pid: pid_t) {
        pendingPIDs.insert(pid)
        schedule()
    }

    private func schedule() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.onChange != nil else { return }
            // Cleared before the scan, so a notification that arrives during it is kept
            // and schedules another pass instead of being wiped with this one.
            self.refreshTask = nil
            let full = self.pendingFull
            let pids = self.pendingPIDs
            self.pendingFull = false
            self.pendingPIDs = []
            if full {
                self.rescanAll()
            } else {
                for pid in pids { self.rescan(pid) }
            }
            guard self.onChange != nil else { return }
            self.publish()
        }
    }

    // MARK: - Reading

    private func rescanAll() {
        let apps = candidates()
        let live = Set(apps.map(\.processIdentifier))
        for pid in cached.keys where !live.contains(pid) { unwatch(pid) }
        var nextCache: [pid_t: [MinimizedDockWindow]] = [:]
        var nextElements: [pid_t: [Int: AXUIElement]] = [:]
        for app in apps {
            watch(app)
            guard let read = read(app) else {
                // Couldn't ask this app (it may be wedged). Keep what we had.
                if let kept = cached[app.processIdentifier] { nextCache[app.processIdentifier] = kept }
                if let kept = elements[app.processIdentifier] { nextElements[app.processIdentifier] = kept }
                continue
            }
            nextCache[app.processIdentifier] = read.windows
            nextElements[app.processIdentifier] = read.elements
            syncWindowNotifications(pid: app.processIdentifier, elements: read.elements)
        }
        cached = nextCache
        elements = nextElements
    }

    private func rescan(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, isCandidate(app) else {
            applicationEnded(pid, publishNow: false)
            return
        }
        watch(app)
        guard let read = read(app) else { return }
        cached[pid] = read.windows
        elements[pid] = read.elements
        syncWindowNotifications(pid: pid, elements: read.elements)
    }

    private struct Read {
        var windows: [MinimizedDockWindow]
        var elements: [Int: AXUIElement]
    }

    /// The app's minimized standard windows. Nil when the app couldn't be read at all,
    /// which is different from it having no minimized windows.
    private func read(_ app: NSRunningApplication) -> Read? {
        guard let url = app.bundleURL else { return Read(windows: [], elements: [:]) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1)
        guard let axWindows: [AXUIElement] = axApp.value(of: kAXWindowsAttribute) else { return nil }
        let item = AppItem(url: url, bundleIdentifier: app.bundleIdentifier)
        var windows: [MinimizedDockWindow] = []
        var elements: [Int: AXUIElement] = [:]
        for element in axWindows {
            guard element.value(of: kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            guard element.value(of: kAXMinimizedAttribute) == true else { continue }
            guard let windowID = windowNumber(of: element) else { continue }
            if elements[windowID] != nil { continue }
            elements[windowID] = element
            windows.append(
                MinimizedDockWindow(
                    id: MinimizedDockWindow.ID(windowID: windowID),
                    processIdentifier: Int32(app.processIdentifier),
                    title: element.value(of: kAXTitleAttribute) ?? "",
                    app: item
                ))
        }
        return Read(windows: windows, elements: elements)
    }

    private func publish() {
        windows = cached.keys.sorted().flatMap { cached[$0] ?? [] }
        onChange?()
    }

    // MARK: - Observers

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard watched[pid] == nil else { return }
        var observer: AXObserver?
        let error = AXObserverCreate(pid, minimizedWindowObserverCallback, &observer)
        guard error == .success, let observer else {
            log.debug("Couldn't watch pid \(pid, privacy: .public): AXError \(error.rawValue, privacy: .public)")
            return
        }
        let application = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        for name in Self.applicationNotes {
            AXObserverAddNotification(observer, application, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        watched[pid] = Watched(observer: observer, windows: [:])
    }

    private func unwatch(_ pid: pid_t) {
        guard let watchedApp = watched.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watchedApp.observer), .commonModes)
    }

    private func syncWindowNotifications(pid: pid_t, elements: [Int: AXUIElement]) {
        guard var watchedApp = watched[pid] else { return }
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        for (id, element) in watchedApp.windows where elements[id] == nil {
            for name in Self.windowNotes {
                AXObserverRemoveNotification(watchedApp.observer, element, name as CFString)
            }
        }
        for (id, element) in elements where watchedApp.windows[id] == nil {
            for name in Self.windowNotes {
                AXObserverAddNotification(watchedApp.observer, element, name as CFString, refcon)
            }
        }
        watchedApp.windows = elements
        watched[pid] = watchedApp
    }

    // MARK: - Which apps

    private func candidates() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter(isCandidate)
    }

    private func isCandidate(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, !app.isTerminated, app.bundleURL != nil else { return false }
        if let own = Bundle.main.bundleIdentifier, app.bundleIdentifier == own { return false }
        return true
    }

    private static func processIdentifier(in note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    private func set(_ attribute: String, to value: Bool, on element: AXUIElement) {
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef)
        if error != .success {
            log.debug("Couldn't set \(attribute, privacy: .public): AXError \(error.rawValue, privacy: .public)")
        }
    }
}

// MARK: - Window number

/// The system's window id, which is also what ScreenCaptureKit lists windows by.
/// `AXWindowNumber` isn't a public constant; the private `_AXUIElementGetWindow` is the
/// fallback, looked up at runtime so a missing symbol doesn't fail to link.
private func windowNumber(of element: AXUIElement) -> Int? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success,
        let number = value as? NSNumber
    {
        let id = number.uint32Value
        if id > 0 { return Int(id) }
    }
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    let getWindow = unsafeBitCast(symbol, to: GetWindow.self)
    var id: UInt32 = 0
    guard getWindow(element, &id) == .success, id > 0 else { return nil }
    return Int(id)
}

// MARK: - Observer callback

/// Retained by the service; the observer's refcon doesn't keep it alive.
private final class AXObservationBox: @unchecked Sendable {
    var onProcess: (@MainActor (pid_t) -> Void)?

    @MainActor
    func fire(_ pid: pid_t) {
        onProcess?(pid)
    }
}

private func minimizedWindowObserverCallback(
    _: AXObserver,
    _ element: AXUIElement,
    _: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let box = Unmanaged<AXObservationBox>.fromOpaque(refcon).takeUnretainedValue()
    let process = pid
    if Thread.isMainThread {
        MainActor.assumeIsolated { box.fire(process) }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { box.fire(process) }
        }
    }
}

private extension AXUIElement {
    func value<Value>(of attribute: String) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}
