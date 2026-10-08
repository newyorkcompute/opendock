import AppKit
import DockCore
import Foundation
import Observation
import os

/// What's playing right now, for the Now Playing widget.
///
/// The monitor owns a list of ``NowPlayingProvider``s and runs the first one; when it
/// reports `.failed`, the next one takes over. Observers only re-render when the track
/// actually changes. It starts working when the first tile calls ``retain()`` and stops
/// (ending any helper process) when the last one calls ``release()``. Use ``shared`` so
/// every tile reads the same data.
@MainActor
@Observable
public final class NowPlayingMonitor {
    /// Process-wide instance shared by all Now Playing tiles.
    public static let shared = NowPlayingMonitor(providers: defaultProviders())

    /// The current item, or `nil` when no player has anything.
    public private(set) var track: NowPlayingTrack?
    /// The current item's cover art, decoded once per artwork.
    public private(set) var artworkImage: NSImage?
    /// Describes the provider in use, for Settings. `nil` until started.
    public private(set) var sourceName: String?
    /// True once every provider has failed.
    public private(set) var isUnavailable = false

    @ObservationIgnored private let providers: [any NowPlayingProvider]
    @ObservationIgnored private var providerIndex = 0
    @ObservationIgnored private var observerCount = 0
    @ObservationIgnored private var isDockVisible = true
    @ObservationIgnored private var runningProvider: (any NowPlayingProvider)?
    @ObservationIgnored private var artworkSource: NowPlayingArtwork?
    @ObservationIgnored private let logger = Logger(subsystem: "com.newyorkcompute.opendock", category: "NowPlaying")

    /// The providers OpenDock ships, in the order they're tried: the system-wide helper,
    /// then scripting Music and Spotify directly.
    public static func defaultProviders() -> [any NowPlayingProvider] {
        var providers: [any NowPlayingProvider] = []
        if let helper = MediaRemoteHelperProvider() { providers.append(helper) }
        providers.append(ScriptedPlayersProvider())
        return providers
    }

    public init(providers: [any NowPlayingProvider]) {
        self.providers = providers
    }

    isolated deinit {
        runningProvider?.stop()
    }

    // MARK: Lifecycle

    /// True while at least one tile is showing.
    public var isActive: Bool { observerCount > 0 }

    /// A tile appeared. The first one starts the provider.
    public func retain() {
        observerCount += 1
        if observerCount == 1 { startCurrentProvider() }
    }

    /// A tile went away. The last one stops the provider.
    public func release() {
        observerCount = max(0, observerCount - 1)
        if observerCount == 0 { stopCurrentProvider() }
    }

    /// Lets polling providers slow down while the dock is hidden.
    public func setDockVisible(_ visible: Bool) {
        isDockVisible = visible
        runningProvider?.setDockVisible(visible)
    }

    private func startCurrentProvider() {
        guard runningProvider == nil, providerIndex < providers.count else {
            isUnavailable = providerIndex >= providers.count
            return
        }
        let provider = providers[providerIndex]
        runningProvider = provider
        sourceName = provider.sourceName
        isUnavailable = false
        provider.setDockVisible(isDockVisible)
        // The provider keeps this handler, so it mustn't keep the provider.
        provider.start { [weak self, weak provider] event in
            guard let self, let provider, self.runningProvider === provider else { return }
            switch event {
            case .track(let track):
                self.apply(track)
            case .failed(let reason):
                self.logger.notice(
                    "Now Playing source \(provider.sourceName, privacy: .public) failed: \(reason, privacy: .public)")
                provider.stop()
                self.runningProvider = nil
                self.providerIndex += 1
                self.apply(nil)
                self.startCurrentProvider()
            }
        }
    }

    private func stopCurrentProvider() {
        runningProvider?.stop()
        runningProvider = nil
        apply(nil)
    }

    // MARK: State

    private func apply(_ updated: NowPlayingTrack?) {
        if updated?.artwork != artworkSource {
            artworkSource = updated?.artwork
            artworkImage = updated?.artwork.flatMap { NSImage(data: $0.data) }
        }
        if updated != track { track = updated }
    }

    // MARK: Player

    /// The running player app, when the track says which one it is.
    public var playerApplication: NSRunningApplication? {
        if let pid = track?.playerPID, let app = NSRunningApplication(processIdentifier: pid) { return app }
        if let bundleID = track?.playerBundleID {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        return nil
    }

    /// "Music", "Spotify", "Chrome", ...
    public var playerName: String? {
        if let name = playerApplication?.localizedName { return name }
        return track?.playerBundleID.map(NowPlayingFormatting.playerName(forBundleID:))
    }

    /// Brings the player to the front.
    public func activatePlayer() {
        playerApplication?.activate()
    }

    // MARK: Commands

    /// Sends a transport command. Play/pause flips the shown state right away so the
    /// button doesn't lag; the player's next report settles it.
    public func send(_ command: NowPlayingCommand) {
        guard let provider = runningProvider else { return }
        provider.send(command)
        guard var optimistic = track else { return }
        switch command {
        case .play: optimistic.isPlaying = true
        case .pause: optimistic.isPlaying = false
        case .togglePlayPause: optimistic.isPlaying.toggle()
        case .nextTrack, .previousTrack: return
        }
        let now = Date()
        optimistic.elapsed = track?.elapsed(at: now)
        optimistic.timestamp = now
        optimistic.playbackRate = optimistic.isPlaying ? 1 : 0
        track = optimistic
    }
}
