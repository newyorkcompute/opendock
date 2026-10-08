import AppKit
import DockCore
import Foundation
import os

/// Runs AppleScript and returns what it printed. A protocol so the provider can be tested
/// without `osascript` or a player.
@MainActor
public protocol AppleScriptRunner {
    /// Runs `script` and returns its result as text, or `nil` if it failed or timed out.
    func run(_ script: String) async -> String?
}

/// Runs scripts with `/usr/bin/osascript` in a child process, off the main thread.
///
/// Because the child is spawned by OpenDock, macOS attributes its Apple Events to OpenDock:
/// the one-time "OpenDock wants access to control Music" prompt uses the app's
/// `NSAppleEventsUsageDescription`, and the decision is stored for the app.
@MainActor
public struct OSAScriptRunner: AppleScriptRunner {
    public var timeout: TimeInterval = 5

    public init() {}

    public func run(_ script: String) async -> String? {
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            Self.execute(script: script, timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    /// Runs `osascript` on a background queue and calls `completion` once with its output,
    /// or `nil` when it fails or outlives `timeout`.
    private nonisolated static func execute(
        script: String, timeout: TimeInterval, completion: @escaping @Sendable (String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-"]
            let input = Pipe()
            let output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
                try input.fileHandleForWriting.close()
            } catch {
                completion(nil)
                return
            }

            // A wedged player can keep osascript waiting; don't let it hold this thread forever.
            let pid = process.processIdentifier
            let watchdog = DispatchWorkItem { kill(pid, SIGTERM) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                completion(nil)
                return
            }
            completion(String(data: data, encoding: .utf8))
        }
    }
}

/// Asks Music and Spotify directly, over Apple Events, what they're playing.
///
/// This is the fallback when the system-wide helper isn't available. It only sees the
/// players it knows (`ScriptedPlayer`), only when they're running, and it has to poll:
/// every 2 seconds while the dock is visible, far less often when hidden, plus straight
/// away when a player posts its `playerInfo`/`PlaybackStateChanged` notification.
@MainActor
public final class ScriptedPlayersProvider: NowPlayingProvider {
    public let sourceName = "Music and Spotify"

    private let players: [ScriptedPlayer]
    private let runner: any AppleScriptRunner
    private let runningBundleIDs: @MainActor () -> Set<String>
    private let fetchURL: @Sendable (URL) async -> Data?

    private var handler: (@MainActor (NowPlayingProviderEvent) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var refreshInFlight: Task<Void, Never>?
    private var isDockVisible = true
    private var observers: [any NSObjectProtocol] = []

    public private(set) var track: NowPlayingTrack?
    private var artworkCache: (reference: String, artwork: NowPlayingArtwork?)?
    private let temporaryArtworkURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("opendock-nowplaying-artwork-\(ProcessInfo.processInfo.processIdentifier)")

    /// - Parameters:
    ///   - runner: Runs AppleScript; the default uses `osascript`.
    ///   - runningBundleIDs: Which bundle IDs are running; the default asks `NSWorkspace`.
    ///   - fetchURL: Downloads artwork for players that publish a URL (Spotify).
    public init(
        players: [ScriptedPlayer] = ScriptedPlayer.allCases,
        runner: any AppleScriptRunner = OSAScriptRunner(),
        runningBundleIDs: @escaping @MainActor () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        fetchURL: @escaping @Sendable (URL) async -> Data? = { url in
            try? await URLSession.shared.data(from: url).0
        }
    ) {
        self.players = players
        self.runner = runner
        self.runningBundleIDs = runningBundleIDs
        self.fetchURL = fetchURL
    }

    isolated deinit {
        stop()
    }

    // MARK: NowPlayingProvider

    public func start(handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void) {
        self.handler = handler
        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo", "com.spotify.client.PlaybackStateChanged",
        ]
        for name in names {
            observers.append(
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshSoon() }
                })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval: Duration = self.isDockVisible ? .seconds(2) : .seconds(30)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        handler = nil
        pollTask?.cancel()
        pollTask = nil
        refreshInFlight?.cancel()
        refreshInFlight = nil
        let center = DistributedNotificationCenter.default()
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        track = nil
    }

    public func send(_ command: NowPlayingCommand) {
        guard let player = targetPlayer() else { return }
        Task {
            _ = await runner.run(player.script(for: command))
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
        }
    }

    public func setDockVisible(_ visible: Bool) {
        guard visible != isDockVisible else { return }
        isDockVisible = visible
        if visible { refreshSoon() }
    }

    // MARK: Refresh

    /// The player a command should go to: the one showing, else any running one.
    func targetPlayer() -> ScriptedPlayer? {
        if let bundleID = track?.playerBundleID, let player = players.first(where: { $0.bundleID == bundleID }) {
            return player
        }
        let running = runningBundleIDs()
        return players.first { running.contains($0.bundleID) }
    }

    private func refreshSoon() {
        guard handler != nil else { return }
        Task { await refresh() }
    }

    /// Asks every running player and publishes the arbiter's pick. Concurrent calls share one read.
    public func refresh() async {
        if let refreshInFlight {
            await refreshInFlight.value
            return
        }
        let task = Task { await self.performRefresh() }
        refreshInFlight = task
        await task.value
        if refreshInFlight == task { refreshInFlight = nil }
    }

    private func performRefresh() async {
        let running = runningBundleIDs()
        let active = players.filter { running.contains($0.bundleID) }
        guard !active.isEmpty else {
            publish(nil)
            return
        }

        var statuses: [(player: ScriptedPlayer, status: ScriptedPlayerStatus)] = []
        for player in active {
            guard let output = await runner.run(player.statusScript) else { continue }
            if let status = player.parseStatus(output) { statuses.append((player, status)) }
        }
        guard handler != nil else { return }

        guard let chosen = NowPlayingArbiter.choose(from: statuses.map { $0.status.track }),
            let match = statuses.first(where: { $0.status.track == chosen })
        else {
            publish(nil)
            return
        }

        var result = match.status.track
        result.artwork = await artwork(for: match.player, status: match.status)
        publish(result)
    }

    private func artwork(for player: ScriptedPlayer, status: ScriptedPlayerStatus) async -> NowPlayingArtwork? {
        guard let reference = status.artworkReference else { return nil }
        if let artworkCache, artworkCache.reference == reference { return artworkCache.artwork }

        var artwork: NowPlayingArtwork?
        if let url = URL(string: reference), let scheme = url.scheme, scheme.hasPrefix("http") {
            if let data = await fetchURL(url), !data.isEmpty {
                artwork = NowPlayingArtwork(data: data, mimeType: nil)
            }
        } else if let script = player.artworkScript(writingTo: temporaryArtworkURL.path) {
            let url = temporaryArtworkURL
            defer { try? FileManager.default.removeItem(at: url) }
            let answer = await runner.run(script)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if answer == "ok", let data = try? Data(contentsOf: url), !data.isEmpty {
                artwork = NowPlayingArtwork(data: data, mimeType: nil)
            }
        }
        artworkCache = (reference, artwork)
        return artwork
    }

    private func publish(_ updated: NowPlayingTrack?) {
        guard let handler else { return }
        guard let updated else {
            if track != nil {
                track = nil
                handler(.track(nil))
            }
            return
        }
        // Polling re-reads the position every time; only report when something else changed
        // or the position drifted from what the previous snapshot predicts.
        if let current = track, Self.isSameState(current, updated) { return }
        track = updated
        handler(.track(updated))
    }

    /// True when `updated` is what `current` predicts for its timestamp, within a second.
    static func isSameState(_ current: NowPlayingTrack, _ updated: NowPlayingTrack) -> Bool {
        guard current.itemIdentity == updated.itemIdentity, current.isPlaying == updated.isPlaying,
            current.duration == updated.duration, current.artwork == updated.artwork
        else { return false }
        guard let updatedElapsed = updated.elapsed, let timestamp = updated.timestamp else {
            return current.elapsed == updated.elapsed
        }
        guard let predicted = current.elapsed(at: timestamp) else { return false }
        return abs(predicted - updatedElapsed) < 1
    }
}
