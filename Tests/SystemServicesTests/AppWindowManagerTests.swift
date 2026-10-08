import Foundation
import Testing

@testable import SystemServices

private enum WindowEvent: Equatable {
    case list(pid_t)
    case minimize(AppWindow.ID)
    case restore(AppWindow.ID)
    case raise(AppWindow.ID)
    case activate(pid_t)
}

/// An app's windows, with no real windows behind them.
@MainActor
private final class FakeWindowBackend: WindowBackend {
    var windows: [AppWindow]
    var events: [WindowEvent] = []

    init(windows: [AppWindow] = []) {
        self.windows = windows
    }

    func windows(ofProcess processIdentifier: pid_t) -> [AppWindow] {
        events.append(.list(processIdentifier))
        return windows
    }

    func setMinimized(_ minimized: Bool, window: AppWindow.ID) {
        events.append(minimized ? .minimize(window) : .restore(window))
    }

    func raise(_ window: AppWindow.ID) { events.append(.raise(window)) }
    func activate(processIdentifier: pid_t) { events.append(.activate(processIdentifier)) }

    /// Only the calls that change something.
    var actions: [WindowEvent] {
        events.filter { if case .list = $0 { false } else { true } }
    }
}

private func window(_ id: Int, _ title: String, minimized: Bool = false, main: Bool = false) -> AppWindow {
    AppWindow(id: id, title: title, isMinimized: minimized, isMain: main)
}

private let pid: pid_t = 42

@MainActor
private func makeManager(_ backend: FakeWindowBackend, trusted: Bool = true) -> AppWindowManager {
    AppWindowManager(
        permission: AccessibilityPermission(backend: FakeAccessibilityBackend(trusted: trusted)), backend: backend)
}

@MainActor
@Suite("App windows")
struct AppWindowManagerTests {
    // MARK: Access

    @Test func doesNothingWithoutAccess() {
        let backend = FakeWindowBackend(windows: [window(1, "Inbox")])
        let manager = makeManager(backend, trusted: false)
        #expect(manager.menuWindows(ofProcess: pid).isEmpty)
        #expect(manager.toggleMinimized(ofProcess: pid) == nil)
        manager.bringToFront(window(1, "Inbox"), ofProcess: pid)
        #expect(backend.events.isEmpty)
    }

    @Test func checksAccessAgainBeforeEveryUse() {
        let accessibility = FakeAccessibilityBackend(trusted: false)
        let backend = FakeWindowBackend(windows: [window(1, "Inbox")])
        let manager = AppWindowManager(permission: AccessibilityPermission(backend: accessibility), backend: backend)
        #expect(manager.menuWindows(ofProcess: pid).isEmpty)
        accessibility.isTrusted = true
        #expect(manager.menuWindows(ofProcess: pid).count == 1)
        #expect(manager.permission.isGranted)
    }

    // MARK: Menu

    @Test func menuListsWindowsByTitle() {
        let backend = FakeWindowBackend(windows: [
            window(1, "Notes 10"),
            window(2, "budget", minimized: true),
            window(3, "Notes 9", main: true),
        ])
        let windows = makeManager(backend).menuWindows(ofProcess: pid)
        #expect(windows.map(\.id) == [2, 3, 1])
        #expect(backend.events == [.list(pid)])
    }

    @Test func bringingAWindowForwardRaisesItAndActivatesTheApp() {
        let backend = FakeWindowBackend()
        makeManager(backend).bringToFront(window(7, "Inbox"), ofProcess: pid)
        #expect(backend.actions == [.raise(7), .activate(pid)])
    }

    @Test func bringingAMinimizedWindowForwardRestoresItFirst() {
        let backend = FakeWindowBackend()
        makeManager(backend).bringToFront(window(7, "Inbox", minimized: true), ofProcess: pid)
        #expect(backend.actions == [.restore(7), .raise(7), .activate(pid)])
    }

    // MARK: Click to minimize

    @Test func minimizesTheVisibleWindows() {
        let backend = FakeWindowBackend(windows: [
            window(1, "A", main: true),
            window(2, "B", minimized: true),
            window(3, "C"),
        ])
        let outcome = makeManager(backend).toggleMinimized(ofProcess: pid)
        #expect(outcome == .minimized)
        #expect(backend.actions == [.minimize(1), .minimize(3)])
    }

    @Test func restoresWhenEverythingIsMinimized() {
        let backend = FakeWindowBackend(windows: [
            window(1, "A", minimized: true),
            window(2, "B", minimized: true, main: true),
        ])
        let outcome = makeManager(backend).toggleMinimized(ofProcess: pid)
        #expect(outcome == .restored)
        #expect(backend.actions == [.restore(1), .restore(2), .raise(2), .activate(pid)])
    }

    @Test func restoringWithoutAMainWindowRaisesTheFrontOne() {
        let backend = FakeWindowBackend(windows: [
            window(4, "Front", minimized: true),
            window(5, "Back", minimized: true),
        ])
        _ = makeManager(backend).toggleMinimized(ofProcess: pid)
        #expect(backend.actions.suffix(2) == [.raise(4), .activate(pid)])
    }

    @Test func clickingAnAppWithNoWindowsIsLeftToOpenIt() {
        let backend = FakeWindowBackend(windows: [])
        #expect(makeManager(backend).toggleMinimized(ofProcess: pid) == nil)
        #expect(backend.actions.isEmpty)
    }

    @Test func minimizingThenRestoringRoundTrips() {
        let backend = FakeWindowBackend(windows: [window(1, "A", main: true), window(2, "B")])
        let manager = makeManager(backend)
        #expect(manager.toggleMinimized(ofProcess: pid) == .minimized)
        backend.windows = backend.windows.map { window($0.id, $0.title, minimized: true, main: $0.isMain) }
        #expect(manager.toggleMinimized(ofProcess: pid) == .restored)
        backend.windows = backend.windows.map { window($0.id, $0.title, main: $0.isMain) }
        #expect(manager.toggleMinimized(ofProcess: pid) == .minimized)
    }
}
