import Foundation

/// Cover art for the current item, as the player handed it over.
public struct NowPlayingArtwork: Sendable, Hashable {
    public let data: Data
    /// MIME type if the player reported one (for example "image/jpeg").
    public let mimeType: String?

    public init(data: Data, mimeType: String?) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// What some media player is playing (or has paused) right now, as a plain value the
/// dock can render. Timing is a snapshot: `elapsed` is the playback position at
/// `timestamp`; use ``elapsed(at:)`` for the position at any later moment.
public struct NowPlayingTrack: Sendable, Hashable {
    public var title: String
    public var artist: String?
    public var album: String?
    /// Length of the item in seconds, if known.
    public var duration: TimeInterval?
    /// Playback position, in seconds, at `timestamp`.
    public var elapsed: TimeInterval?
    /// When `elapsed` was measured.
    public var timestamp: Date?
    public var isPlaying: Bool
    /// 1 while playing at normal speed, 0 while paused. Used to extrapolate `elapsed`.
    public var playbackRate: Double
    /// Bundle identifier of the player, if known.
    public var playerBundleID: String?
    /// Process identifier of the player, if known.
    public var playerPID: Int32?
    public var artwork: NowPlayingArtwork?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        timestamp: Date? = nil,
        isPlaying: Bool,
        playbackRate: Double? = nil,
        playerBundleID: String? = nil,
        playerPID: Int32? = nil,
        artwork: NowPlayingArtwork? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate ?? (isPlaying ? 1 : 0)
        self.playerBundleID = playerBundleID
        self.playerPID = playerPID
        self.artwork = artwork
    }

    /// Playback position at `date`, extrapolated from the snapshot while playing and
    /// clamped to the item's duration. `nil` when the player reported no position.
    public func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var position = elapsed
        if isPlaying, let timestamp {
            position += max(0, date.timeIntervalSince(timestamp)) * max(0, playbackRate)
        }
        if let duration, duration > 0 { position = min(position, duration) }
        return max(0, position)
    }

    /// Fraction of the item played at `date`, 0...1, or `nil` without a duration.
    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0, let position = elapsed(at: date) else { return nil }
        return min(1, max(0, position / duration))
    }

    /// Everything that identifies the item itself, ignoring playback state and timing.
    /// Two snapshots of the same song a few seconds apart compare equal here.
    public var itemIdentity: NowPlayingItemIdentity {
        NowPlayingItemIdentity(title: title, artist: artist, album: album, playerBundleID: playerBundleID)
    }
}

/// Identity of a played item, independent of position and play/pause state.
public struct NowPlayingItemIdentity: Sendable, Hashable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let playerBundleID: String?
}

/// Transport commands every source supports.
public enum NowPlayingCommand: String, Sendable, CaseIterable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// Text formatting shared by the tile and the popout.
public enum NowPlayingFormatting {
    /// "0:07", "3:05" or "1:02:33".
    public static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "-2:13": time left in the item at `date`, or `nil` without a duration.
    public static func remaining(for track: NowPlayingTrack, at date: Date) -> String? {
        guard let duration = track.duration, let elapsed = track.elapsed(at: date) else { return nil }
        return "-" + time(max(0, duration - elapsed))
    }

    /// The artist, or a placeholder when the player didn't report one.
    public static func artistLine(for track: NowPlayingTrack) -> String {
        let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? "Unknown Artist" : artist
    }

    /// A readable name for a player given only its bundle identifier: the last component,
    /// capitalized, with a few well-known players spelled the way their apps are.
    public static func playerName(forBundleID bundleID: String) -> String {
        if let known = knownPlayerNames[bundleID] { return known }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        guard let first = last.first else { return bundleID }
        return first.uppercased() + last.dropFirst()
    }

    private static let knownPlayerNames: [String: String] = [
        "com.apple.Music": "Music",
        "com.apple.Podcasts": "Podcasts",
        "com.apple.TV": "TV",
        "com.apple.Safari": "Safari",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.spotify.client": "Spotify",
        "com.google.Chrome": "Chrome",
        "org.mozilla.firefox": "Firefox",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Edge",
        "com.tidal.desktop": "TIDAL",
        "org.videolan.vlc": "VLC",
        "com.colliderli.iina": "IINA",
    ]
}

/// Picks the track to show when more than one player reports something.
public enum NowPlayingArbiter {
    /// The playing track if there is exactly one, otherwise the most recently updated
    /// candidate, preferring playing ones. `nil` when there are no candidates.
    public static func choose(from candidates: [NowPlayingTrack]) -> NowPlayingTrack? {
        let playing = candidates.filter(\.isPlaying)
        if playing.count == 1 { return playing[0] }
        let pool = playing.isEmpty ? candidates : playing
        return pool.max { lhs, rhs in
            (lhs.timestamp ?? .distantPast) < (rhs.timestamp ?? .distantPast)
        }
    }
}
