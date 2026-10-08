import DockCore
import Foundation
import Testing

@testable import SystemServices

private let epoch = Date(timeIntervalSince1970: 1_760_000_000)

/// A scripted Now Playing source the tests drive by hand.
@MainActor
private final class FakeProvider: NowPlayingProvider {
    let sourceName: String
    var handler: (@MainActor (NowPlayingProviderEvent) -> Void)?
    var starts = 0
    var stops = 0
    var sent: [NowPlayingCommand] = []
    var visibility: [Bool] = []

    init(name: String) { sourceName = name }

    func start(handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void) {
        starts += 1
        self.handler = handler
    }

    func stop() {
        stops += 1
        handler = nil
    }

    func send(_ command: NowPlayingCommand) { sent.append(command) }
    func setDockVisible(_ visible: Bool) { visibility.append(visible) }
}

@Suite("NowPlayingMonitor")
@MainActor
struct NowPlayingMonitorTests {
    private let song = NowPlayingTrack(
        title: "Song", artist: "Band", duration: 200, elapsed: 20, timestamp: epoch, isPlaying: true,
        playerBundleID: "com.spotify.client")

    @Test func startsWithTheFirstTileAndStopsWithTheLast() {
        let provider = FakeProvider(name: "fake")
        let monitor = NowPlayingMonitor(providers: [provider])
        #expect(provider.starts == 0)

        monitor.retain()
        monitor.retain()
        #expect(provider.starts == 1)
        #expect(monitor.isActive)
        #expect(monitor.sourceName == "fake")

        provider.handler?(.track(song))
        #expect(monitor.track == song)

        monitor.release()
        #expect(provider.stops == 0)
        monitor.release()
        #expect(provider.stops == 1)
        #expect(!monitor.isActive)
        #expect(monitor.track == nil, "nothing is shown once the source is stopped")
    }

    @Test func fallsBackWhenAProviderFails() {
        let helper = FakeProvider(name: "helper")
        let scripted = FakeProvider(name: "scripted")
        let monitor = NowPlayingMonitor(providers: [helper, scripted])
        monitor.retain()
        helper.handler?(.track(song))

        helper.handler?(.failed("perl is gone"))
        #expect(helper.stops == 1)
        #expect(scripted.starts == 1)
        #expect(monitor.sourceName == "scripted")
        #expect(monitor.track == nil)
        #expect(!monitor.isUnavailable)

        scripted.handler?(.failed("osascript is gone too"))
        #expect(monitor.isUnavailable)
        #expect(monitor.sourceName == "scripted")

        monitor.release()
        monitor.retain()
        #expect(scripted.starts == 1, "a failed provider isn't retried")
        #expect(monitor.isUnavailable)
    }

    @Test func forwardsCommandsAndFlipsPlayPauseOptimistically() {
        let provider = FakeProvider(name: "fake")
        let monitor = NowPlayingMonitor(providers: [provider])
        monitor.retain()
        provider.handler?(.track(song))

        monitor.send(.togglePlayPause)
        #expect(provider.sent == [.togglePlayPause])
        #expect(monitor.track?.isPlaying == false)
        #expect(monitor.track?.playbackRate == 0)
        #expect(monitor.track?.elapsed.map { $0 >= 20 } == true)

        monitor.send(.nextTrack)
        #expect(provider.sent == [.togglePlayPause, .nextTrack])
        #expect(monitor.track?.isPlaying == false, "skipping doesn't guess at the new state")

        monitor.send(.play)
        #expect(monitor.track?.isPlaying == true)
        #expect(monitor.track?.playbackRate == 1)
    }

    @Test func ignoresCommandsWhileStopped() {
        let provider = FakeProvider(name: "fake")
        let monitor = NowPlayingMonitor(providers: [provider])
        monitor.send(.play)
        #expect(provider.sent.isEmpty)
    }

    @Test func passesDockVisibilityOn() {
        let provider = FakeProvider(name: "fake")
        let monitor = NowPlayingMonitor(providers: [provider])
        monitor.setDockVisible(false)
        monitor.retain()
        #expect(provider.visibility == [false], "the provider starts with the dock's current visibility")
        monitor.setDockVisible(true)
        #expect(provider.visibility == [false, true])
    }

    @Test func decodesArtworkOncePerImage() {
        let provider = FakeProvider(name: "fake")
        let monitor = NowPlayingMonitor(providers: [provider])
        monitor.retain()
        var withArt = song
        withArt.artwork = NowPlayingArtwork(data: onePixelPNG, mimeType: "image/png")
        provider.handler?(.track(withArt))
        let first = monitor.artworkImage
        #expect(first != nil)

        var paused = withArt
        paused.isPlaying = false
        provider.handler?(.track(paused))
        #expect(monitor.artworkImage === first, "same artwork bytes, same image")

        provider.handler?(.track(song))
        #expect(monitor.artworkImage == nil)
    }

    @Test func ignoresEventsFromAReplacedProvider() {
        let helper = FakeProvider(name: "helper")
        let scripted = FakeProvider(name: "scripted")
        let monitor = NowPlayingMonitor(providers: [helper, scripted])
        monitor.retain()
        let stale = helper.handler
        helper.handler?(.failed("gone"))
        stale?(.track(song))
        #expect(monitor.track == nil)
    }
}

/// Answers status scripts with canned lines, keyed by the bundle ID the script targets.
@MainActor
private final class FakeRunner: AppleScriptRunner {
    var outputs: [String: String] = [:]
    var scripts: [String] = []

    func run(_ script: String) async -> String? {
        scripts.append(script)
        for (bundleID, output) in outputs where script.contains("\"\(bundleID)\"") {
            return output
        }
        return nil
    }
}

@Suite("ScriptedPlayersProvider")
@MainActor
struct ScriptedPlayersProviderTests {
    private let sep = String(ScriptedPlayer.fieldSeparator)

    private func statusLine(_ state: String, _ title: String, artwork: String) -> String {
        [state, title, "Band", "Album", "200000", "20000", artwork].joined(separator: sep)
    }

    @Test func picksThePlayingPlayerAndFetchesItsArtwork() async {
        let runner = FakeRunner()
        runner.outputs[ScriptedPlayer.music.bundleID] = statusLine("paused", "Music song", artwork: "ID1")
        runner.outputs[ScriptedPlayer.spotify.bundleID] = statusLine(
            "playing", "Spotify song", artwork: "https://example.com/art.jpg")
        let fetched = FetchLog()
        let provider = ScriptedPlayersProvider(
            runner: runner,
            runningBundleIDs: { [ScriptedPlayer.music.bundleID, ScriptedPlayer.spotify.bundleID] },
            fetchURL: { url in
                fetched.append(url)
                return Data([1, 2, 3])
            })
        var events: [NowPlayingTrack?] = []
        provider.start { if case .track(let track) = $0 { events.append(track) } }
        await provider.refresh()

        #expect(events.count == 1)
        #expect(events.first??.title == "Spotify song")
        #expect(events.first??.isPlaying == true)
        #expect(events.first??.duration == 200)
        #expect(events.first??.elapsed == 20)
        #expect(events.first??.artwork == NowPlayingArtwork(data: Data([1, 2, 3]), mimeType: nil))
        #expect(fetched.urls.map(\.absoluteString) == ["https://example.com/art.jpg"])
        #expect(provider.targetPlayer() == .spotify)

        // Polling again with the same state (allowing for playback progress) is quiet,
        // and artwork isn't downloaded twice.
        await provider.refresh()
        #expect(events.count == 1)
        #expect(fetched.urls.count == 1)
        provider.stop()
    }

    @Test func skipsPlayersThatArentRunning() async {
        let runner = FakeRunner()
        runner.outputs[ScriptedPlayer.music.bundleID] = statusLine("playing", "Music song", artwork: "")
        let provider = ScriptedPlayersProvider(runner: runner, runningBundleIDs: { [] }, fetchURL: { _ in nil })
        var events: [NowPlayingTrack?] = []
        provider.start { if case .track(let track) = $0 { events.append(track) } }
        await provider.refresh()
        #expect(runner.scripts.isEmpty, "a player that isn't running is never scripted, so it's never launched")
        #expect(events.isEmpty, "nothing changed, so nothing is reported")
        provider.stop()
    }

    @Test func reportsWhenTheTrackGoesAway() async {
        let runner = FakeRunner()
        runner.outputs[ScriptedPlayer.music.bundleID] = statusLine("playing", "Music song", artwork: "")
        let provider = ScriptedPlayersProvider(
            runner: runner, runningBundleIDs: { [ScriptedPlayer.music.bundleID] }, fetchURL: { _ in nil })
        var events: [NowPlayingTrack?] = []
        provider.start { if case .track(let track) = $0 { events.append(track) } }
        await provider.refresh()
        runner.outputs[ScriptedPlayer.music.bundleID] = "stopped"
        await provider.refresh()
        #expect(events.count == 2)
        #expect(events.last! == nil)
        provider.stop()
    }

    /// Shown again after a hidden stretch, the provider reads right away instead of at the
    /// end of the long hidden interval.
    @Test func readsAgainAsSoonAsTheDockIsShown() async {
        let runner = FakeRunner()
        runner.outputs[ScriptedPlayer.music.bundleID] = statusLine("playing", "Music song", artwork: "")
        let provider = ScriptedPlayersProvider(
            runner: runner, runningBundleIDs: { [ScriptedPlayer.music.bundleID] }, fetchURL: { _ in nil })
        provider.start { _ in }
        await eventually { !runner.scripts.isEmpty }
        let readsWhileShown = runner.scripts.count

        provider.setDockVisible(false)
        provider.setDockVisible(true)
        await eventually { runner.scripts.count > readsWhileShown }
        #expect(runner.scripts.count > readsWhileShown)
        provider.stop()
    }

    /// Waits for the provider's own polling to catch up, well within one visible interval.
    private func eventually(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 100 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func sendsCommandsToTheShownPlayerOrAnyRunningOne() async {
        let runner = FakeRunner()
        let provider = ScriptedPlayersProvider(
            runner: runner, runningBundleIDs: { [ScriptedPlayer.spotify.bundleID] }, fetchURL: { _ in nil })
        #expect(provider.targetPlayer() == .spotify)
        let nobody = ScriptedPlayersProvider(runner: runner, runningBundleIDs: { [] }, fetchURL: { _ in nil })
        #expect(nobody.targetPlayer() == nil)
    }

    @Test func sameStateToleratesPlaybackProgress() {
        let before = NowPlayingTrack(title: "Song", duration: 200, elapsed: 20, timestamp: epoch, isPlaying: true)
        var later = before
        later.elapsed = 22.4
        later.timestamp = epoch.addingTimeInterval(2)
        #expect(ScriptedPlayersProvider.isSameState(before, later))

        var seeked = later
        seeked.elapsed = 90
        #expect(!ScriptedPlayersProvider.isSameState(before, seeked))

        var paused = later
        paused.isPlaying = false
        #expect(!ScriptedPlayersProvider.isSameState(before, paused))
    }
}

private final class FetchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []
    var urls: [URL] { lock.withLock { _urls } }
    func append(_ url: URL) { lock.withLock { _urls.append(url) } }
}

/// A valid 1x1 PNG.
private let onePixelPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
