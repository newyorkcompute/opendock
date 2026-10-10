import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import DockCore
@testable import SystemServices

/// Minimized windows with no Accessibility server behind them.
@MainActor
private final class FakeMinimizedWindowSource: MinimizedWindowSource {
    var windows: [MinimizedDockWindow] = []
    private var onChange: (@MainActor () -> Void)?
    var starts = 0
    var stops = 0
    var restored: [Int] = []
    var closed: [Int] = []

    func start(_ onChange: @escaping @MainActor () -> Void) {
        starts += 1
        self.onChange = onChange
    }

    func stop() {
        stops += 1
        onChange = nil
    }

    func restore(_ window: MinimizedDockWindow) { restored.append(window.id.windowID) }
    func close(_ window: MinimizedDockWindow) { closed.append(window.id.windowID) }

    func emit() { onChange?() }
}

/// Records capture requests. `image` is a 1×1 bitmap, enough to prove one was stored.
@MainActor
private final class FakeThumbnailCapturer: WindowThumbnailCapturing {
    var calls: [[Int]] = []
    let image: CGImage

    init() {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        image = context!.makeImage()!
    }

    func capture(windowIDs: [Int]) async -> [Int: CGImage] {
        await Task.yield()
        calls.append(windowIDs)
        return Dictionary(uniqueKeysWithValues: windowIDs.map { ($0, image) })
    }
}

@MainActor
private struct MonitorFixture {
    var source = FakeMinimizedWindowSource()
    var capturer = FakeThumbnailCapturer()
    var accessibility = FakeAccessibilityBackend(trusted: true)
    var screenRecording = FakeScreenRecordingBackend()
    var monitor: MinimizedWindowMonitor

    init() {
        monitor = MinimizedWindowMonitor(
            accessibility: AccessibilityPermission(backend: accessibility),
            screenRecording: ScreenRecordingPermission(backend: screenRecording),
            source: source,
            thumbnails: capturer
        )
    }
}

private func window(_ id: Int, _ title: String) -> MinimizedDockWindow {
    MinimizedDockWindow(
        id: MinimizedDockWindow.ID(windowID: id),
        processIdentifier: 10,
        title: title,
        app: AppItem(url: URL(fileURLWithPath: "/Applications/Mail.app"), bundleIdentifier: "com.apple.mail")
    )
}

/// Lets the monitor's thumbnail task run. It hops off the main actor only for the capture.
@MainActor
private func settle() async {
    for _ in 0 ..< 8 { await Task.yield() }
}

@MainActor
@Suite("Minimized window monitor")
struct MinimizedWindowMonitorTests {
    @Test func nothingRunsWithoutAccessibilityAccess() {
        let fixture = MonitorFixture()
        fixture.accessibility.isTrusted = false
        fixture.source.windows = [window(1, "Inbox")]
        fixture.monitor.setEnabled(true)
        #expect(fixture.source.starts == 0)
        #expect(fixture.monitor.windows.isEmpty)
        #expect(fixture.capturer.calls.isEmpty)
    }

    @Test func nothingRunsWhileTheSettingIsOff() {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(1, "Inbox")]
        fixture.monitor.setEnabled(false)
        #expect(fixture.source.starts == 0)
        #expect(fixture.monitor.windows.isEmpty)
    }

    @Test func showsWindowsOnceAccessAndTheSettingAllowIt() {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(2, "Sent"), window(2, "Sent again"), window(1, "Inbox")]
        fixture.monitor.setEnabled(true)
        #expect(fixture.source.starts == 1)
        #expect(fixture.monitor.windows.map(\.id.windowID) == [2, 1])
        #expect(fixture.monitor.windows[0].title == "Sent again")
        // Turning the setting on again doesn't start a second observer.
        fixture.monitor.setEnabled(true)
        #expect(fixture.source.starts == 1)
    }

    @Test func updatesFromNotificationsAndKeepsOrder() {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(1, "One"), window(2, "Two")]
        fixture.monitor.setEnabled(true)
        fixture.source.windows = [window(3, "Three"), window(1, "One renamed")]
        fixture.source.emit()
        #expect(fixture.monitor.windows.map(\.id.windowID) == [1, 3])
        #expect(fixture.monitor.windows[0].title == "One renamed")
    }

    @Test func turningTheSettingOffStopsAndForgetsTheWindows() {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(1, "Inbox")]
        fixture.monitor.setEnabled(true)
        fixture.monitor.setEnabled(false)
        #expect(fixture.source.stops == 1)
        #expect(fixture.monitor.windows.isEmpty)
        fixture.source.windows = [window(4, "Later")]
        fixture.source.emit()
        #expect(fixture.monitor.windows.isEmpty)
    }

    @Test func losingAccessStops() {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(1, "Inbox")]
        fixture.monitor.setEnabled(true)
        fixture.accessibility.isTrusted = false
        fixture.monitor.noteAppBecameActive()
        #expect(fixture.source.stops == 1)
        #expect(fixture.monitor.windows.isEmpty)
        #expect(fixture.source.starts == 1)
    }

    @Test func regainingAccessStartsAgain() {
        let fixture = MonitorFixture()
        fixture.accessibility.isTrusted = false
        fixture.monitor.setEnabled(true)
        #expect(fixture.source.starts == 0)
        fixture.accessibility.isTrusted = true
        fixture.source.windows = [window(5, "Back")]
        fixture.monitor.noteAppBecameActive()
        #expect(fixture.source.starts == 1)
        #expect(fixture.monitor.windows.map(\.title) == ["Back"])
    }

    @Test func restoreAndCloseDoNothingWithoutAccess() {
        let fixture = MonitorFixture()
        fixture.accessibility.isTrusted = false
        fixture.monitor.restore(window(7, "Inbox"))
        fixture.monitor.close(window(7, "Inbox"))
        #expect(fixture.source.restored.isEmpty)
        #expect(fixture.source.closed.isEmpty)
    }

    @Test func restoreUnminimizesAndCloseCloses() {
        let fixture = MonitorFixture()
        fixture.monitor.setEnabled(true)
        fixture.monitor.restore(window(7, "Inbox"))
        fixture.monitor.close(window(8, "Sent"))
        #expect(fixture.source.restored == [7])
        #expect(fixture.source.closed == [8])
    }

    @Test func thumbnailsAreNotCapturedWithoutScreenRecording() async {
        let fixture = MonitorFixture()
        fixture.source.windows = [window(7, "Inbox")]
        fixture.monitor.setEnabled(true)
        await settle()
        #expect(fixture.capturer.calls.isEmpty)
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 7)) == nil)
    }

    @Test func thumbnailsAreCapturedWhenScreenRecordingIsAlreadyGranted() async {
        let fixture = MonitorFixture()
        fixture.screenRecording.isGranted = true
        // The permission object read the backend at init, before this grant.
        #expect(fixture.monitor.screenRecording.refresh())
        fixture.source.windows = [window(7, "Inbox"), window(8, "Sent")]
        fixture.monitor.setEnabled(true)
        await settle()
        #expect(fixture.capturer.calls == [[7, 8]])
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 7)) != nil)
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 8)) != nil)

        fixture.source.emit()
        await settle()
        // Still minimized, so the capture isn't repeated.
        #expect(fixture.capturer.calls.count == 1)

        fixture.source.windows = [window(8, "Sent")]
        fixture.source.emit()
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 7)) == nil)
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 8)) != nil)
    }

    @Test func takingScreenRecordingAwayDropsThumbnailsWithoutAnotherCapture() async {
        let fixture = MonitorFixture()
        fixture.screenRecording.isGranted = true
        #expect(fixture.monitor.screenRecording.refresh())
        fixture.source.windows = [window(7, "Inbox")]
        fixture.monitor.setEnabled(true)
        await settle()
        #expect(fixture.capturer.calls.count == 1)

        fixture.screenRecording.isGranted = false
        fixture.monitor.refreshThumbnails()
        #expect(fixture.monitor.thumbnail(for: MinimizedDockWindow.ID(windowID: 7)) == nil)
        #expect(fixture.capturer.calls.count == 1)
    }
}
