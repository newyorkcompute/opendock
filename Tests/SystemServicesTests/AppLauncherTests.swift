import AppKit
import DockCore
import Testing
@testable import SystemServices

private enum LaunchEvent: Equatable {
    case unhide
    case activate(allWindows: Bool)
    case openApplication(URL, activates: Bool, newInstance: Bool)
    case open(URL, activates: Bool)
    case reveal([URL])
}

@MainActor
private final class Recorder {
    var events: [LaunchEvent] = []
}

@MainActor
private struct FakeWorkspace: AppWorkspace {
    let recorder: Recorder

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) {
        recorder.events.append(.openApplication(
            url,
            activates: configuration.activates,
            newInstance: configuration.createsNewApplicationInstance
        ))
    }

    func open(_ url: URL, configuration: NSWorkspace.OpenConfiguration) {
        recorder.events.append(.open(url, activates: configuration.activates))
    }

    func activateFileViewerSelecting(_ urls: [URL]) {
        recorder.events.append(.reveal(urls))
    }
}

@MainActor
private final class FakeRunningApp: RunningAppHandle {
    let recorder: Recorder
    let bundleURL: URL?
    var isHidden: Bool

    init(recorder: Recorder, bundleURL: URL?, isHidden: Bool = false) {
        self.recorder = recorder
        self.bundleURL = bundleURL
        self.isHidden = isHidden
    }

    func unhide() -> Bool {
        isHidden = false
        recorder.events.append(.unhide)
        return true
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        recorder.events.append(.activate(allWindows: options.contains(.activateAllWindows)))
        return true
    }
}

@MainActor
private struct FakeLookup: RunningAppLookup {
    var app: FakeRunningApp?

    func runningApp(bundleIdentifier: String?, bundleURL: URL) -> (any RunningAppHandle)? {
        app
    }
}

@MainActor
@Suite("App launcher")
struct AppLauncherTests {
    private let recorder = Recorder()
    private var workspace: FakeWorkspace { FakeWorkspace(recorder: recorder) }

    private let safari = AppItem(url: URL(filePath: "/Applications/Safari.app"), bundleIdentifier: "com.apple.Safari")
    private let finder = AppItem(
        url: URL(filePath: "/System/Library/CoreServices/Finder.app"),
        bundleIdentifier: "com.apple.finder"
    )

    @Test func launchesAppThatIsNotRunning() {
        AppLauncher.open(safari, running: FakeLookup(app: nil), workspace: workspace)
        #expect(recorder.events == [.openApplication(safari.url, activates: true, newInstance: false)])
    }

    @Test func activatesAndReopensRunningApp() {
        let running = FakeRunningApp(recorder: recorder, bundleURL: safari.url)
        AppLauncher.open(safari, running: FakeLookup(app: running), workspace: workspace)
        #expect(recorder.events == [
            .activate(allWindows: true),
            .openApplication(safari.url, activates: true, newInstance: false),
        ])
    }

    @Test func reopensRunningFinder() {
        let running = FakeRunningApp(recorder: recorder, bundleURL: finder.url)
        AppLauncher.open(finder, running: FakeLookup(app: running), workspace: workspace)
        #expect(recorder.events.last == .openApplication(finder.url, activates: true, newInstance: false))
    }

    @Test func unhidesHiddenAppBeforeActivating() {
        let running = FakeRunningApp(recorder: recorder, bundleURL: safari.url, isHidden: true)
        AppLauncher.open(safari, running: FakeLookup(app: running), workspace: workspace)
        #expect(recorder.events == [
            .unhide,
            .activate(allWindows: true),
            .openApplication(safari.url, activates: true, newInstance: false),
        ])
        #expect(!running.isHidden)
    }

    @Test func reopensTheRunningCopyRatherThanThePinnedOne() {
        let otherCopy = URL(filePath: "/Users/me/Downloads/Safari.app")
        let running = FakeRunningApp(recorder: recorder, bundleURL: otherCopy)
        AppLauncher.open(safari, running: FakeLookup(app: running), workspace: workspace)
        #expect(recorder.events.last == .openApplication(otherCopy, activates: true, newInstance: false))
    }

    @Test func fallsBackToPinnedURLWhenRunningAppHasNoBundle() {
        let running = FakeRunningApp(recorder: recorder, bundleURL: nil)
        AppLauncher.open(safari, running: FakeLookup(app: running), workspace: workspace)
        #expect(recorder.events.last == .openApplication(safari.url, activates: true, newInstance: false))
    }

    @Test func newInstanceAlwaysLaunches() {
        AppLauncher.openNewInstance(safari, workspace: workspace)
        #expect(recorder.events == [.openApplication(safari.url, activates: true, newInstance: true)])
    }

    @Test func opensFolderAndActivatesItsHandler() {
        let folder = FolderItem(url: URL(filePath: "/Users/me/Downloads", directoryHint: .isDirectory))
        AppLauncher.open(folder, workspace: workspace)
        #expect(recorder.events == [.open(folder.url, activates: true)])
    }

    @Test func revealsInFinder() {
        AppLauncher.revealInFinder(safari.url, workspace: workspace)
        #expect(recorder.events == [.reveal([safari.url])])
    }
}
