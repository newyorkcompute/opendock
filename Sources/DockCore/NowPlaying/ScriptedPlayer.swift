import Foundation

/// A media player the dock can ask directly, over Apple Events, when the system-wide
/// Now Playing helper isn't available. `SystemServices` runs these scripts with
/// `osascript`; this type only knows the scripts and how to read their output, so the
/// parsing can be tested without a player installed.
public enum ScriptedPlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    public var bundleID: String { rawValue }

    public var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// The field separator the status scripts use: ASCII unit separator, which never
    /// appears in titles.
    public static let fieldSeparator: Character = "\u{1F}"

    /// Returns one line: `stopped`, or `state␟title␟artist␟album␟durationMillis␟positionMillis␟artworkRef`.
    /// Numbers are integers so the output doesn't depend on the system decimal separator.
    /// `artworkRef` is whatever identifies the current artwork: Spotify's artwork URL, or
    /// the track's persistent ID in Music.
    public var statusScript: String {
        // Spotify reports durations in milliseconds and positions in seconds; Music reports both in seconds.
        let durationExpression = self == .spotify ? "duration of t" : "round ((duration of t) * 1000)"
        let artworkExpression = self == .spotify ? "artwork url of t" : "persistent ID of t"
        return """
            on str(v)
                if v is missing value then return ""
                try
                    return v as text
                on error
                    return ""
                end try
            end str
            on millis(v)
                try
                    return (v as integer) as text
                on error
                    return ""
                end try
            end millis
            set sep to character id 31
            tell application id "\(bundleID)"
                set s to player state
                if s is stopped then return "stopped"
                set stateText to "paused"
                if s is playing then set stateText to "playing"
                try
                    set t to current track
                on error
                    return "stopped"
                end try
                set titleText to my str(name of t)
                set artistText to my str(artist of t)
                set albumText to my str(album of t)
                set durationText to ""
                try
                    set durationText to my millis(\(durationExpression))
                end try
                set positionText to ""
                try
                    set positionText to my millis(round ((player position) * 1000))
                end try
                set artworkText to ""
                try
                    set artworkText to my str(\(artworkExpression))
                end try
                return stateText & sep & titleText & sep & artistText & sep & albumText & sep & durationText & sep & positionText & sep & artworkText
            end tell
            """
    }

    /// The script for a transport command.
    public func script(for command: NowPlayingCommand) -> String {
        let verb =
            switch command {
            case .play: "play"
            case .pause: "pause"
            case .togglePlayPause: "playpause"
            case .nextTrack: "next track"
            case .previousTrack: "previous track"
            }
        return "tell application id \"\(bundleID)\" to \(verb)"
    }

    /// Music only: writes the current track's artwork to `path` and returns `ok`, or `none`
    /// when the track has no artwork. Spotify exposes artwork as a URL instead (see
    /// ``statusScript``).
    public func artworkScript(writingTo path: String) -> String? {
        guard self == .music else { return nil }
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
            tell application id "\(bundleID)"
                try
                    set artworkData to data of artwork 1 of current track
                on error
                    return "none"
                end try
            end tell
            set f to open for access (POSIX file "\(escaped)") with write permission
            try
                set eof f to 0
                write artworkData to f
            end try
            close access f
            return "ok"
            """
    }

    /// Reads a line produced by ``statusScript``. `nil` when the player is stopped or the
    /// output isn't understood.
    public func parseStatus(_ output: String, now: Date = Date()) -> ScriptedPlayerStatus? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line != "stopped" else { return nil }
        let fields = line.split(separator: Self.fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 7 else { return nil }

        let title = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let isPlaying = fields[0] == "playing"
        let duration = Self.seconds(fromMillis: fields[4])
        let position = Self.seconds(fromMillis: fields[5])
        let artworkRef = fields[6].trimmingCharacters(in: .whitespacesAndNewlines)

        let track = NowPlayingTrack(
            title: title,
            artist: Self.nonEmpty(fields[2]),
            album: Self.nonEmpty(fields[3]),
            duration: duration,
            elapsed: position,
            timestamp: now,
            isPlaying: isPlaying,
            playerBundleID: bundleID
        )
        return ScriptedPlayerStatus(track: track, artworkReference: artworkRef.isEmpty ? nil : artworkRef)
    }

    private static func seconds(fromMillis field: String) -> TimeInterval? {
        guard let millis = Int(field.trimmingCharacters(in: .whitespaces)), millis > 0 else { return nil }
        return TimeInterval(millis) / 1000
    }

    private static func nonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A scripted player's answer: the track and whatever identifies its artwork.
public struct ScriptedPlayerStatus: Sendable, Equatable {
    public var track: NowPlayingTrack
    /// Spotify: an `https` artwork URL. Music: the track's persistent ID, which changes
    /// exactly when the artwork needs to be fetched again.
    public var artworkReference: String?

    public init(track: NowPlayingTrack, artworkReference: String?) {
        self.track = track
        self.artworkReference = artworkReference
    }
}
