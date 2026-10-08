import Foundation

/// One line of the Now Playing helper's output, which `SystemServices` runs inside
/// `/usr/bin/perl` to read the system-wide Now Playing state (see `NowPlayingHelper`).
///
/// The helper writes one JSON object per line. Every message has a `kind`:
/// - `nowPlaying`: a player has an item. `pid` and `title` are always present. Artwork is
///   sent only when it changes; `hasArtwork` tells the reader whether to keep the previous
///   artwork (`true` without `artworkData`) or drop it (`false`).
/// - `idle`: no player has anything to show.
///
/// Both ends of the pipe ship in the same app bundle, so the format can change freely
/// as long as both sides change together.
public struct NowPlayingHelperMessage: Decodable, Sendable, Equatable {
    public enum Kind: String, Decodable, Sendable {
        case nowPlaying
        case idle
    }

    public var kind: Kind
    public var pid: Int32?
    public var bundleIdentifier: String?
    public var playing: Bool?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var elapsed: Double?
    /// Seconds since 1970 at which `elapsed` was measured.
    public var timestamp: Double?
    public var rate: Double?
    public var hasArtwork: Bool?
    /// Base64-encoded image data, present only when the artwork changed.
    public var artworkData: String?
    public var artworkMimeType: String?

    /// Parses one line of helper output. Returns `nil` for blank lines and anything
    /// that isn't a message, so a stray diagnostic can't take the stream down.
    public static func parse(line: String) -> NowPlayingHelperMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NowPlayingHelperMessage.self, from: data)
    }

    /// The track this message describes, carrying unchanged artwork over from `previous`.
    public func track(previous: NowPlayingTrack?) -> NowPlayingTrack? {
        guard kind == .nowPlaying, let title, !title.isEmpty else { return nil }

        var artwork: NowPlayingArtwork?
        if let artworkData, let data = Data(base64Encoded: artworkData), !data.isEmpty {
            artwork = NowPlayingArtwork(data: data, mimeType: artworkMimeType)
        } else if hasArtwork == true {
            artwork = previous?.artwork
        }

        let playing = playing ?? ((rate ?? 0) > 0)
        return NowPlayingTrack(
            title: title,
            artist: artist.flatMap(Self.nonEmpty),
            album: album.flatMap(Self.nonEmpty),
            duration: duration.flatMap { $0 > 0 ? $0 : nil },
            elapsed: elapsed.map { max(0, $0) },
            timestamp: timestamp.map { Date(timeIntervalSince1970: $0) },
            isPlaying: playing,
            playbackRate: rate ?? (playing ? 1 : 0),
            playerBundleID: bundleIdentifier.flatMap(Self.nonEmpty)
                ?? (previous?.playerPID == pid ? previous?.playerBundleID : nil),
            playerPID: pid,
            artwork: artwork
        )
    }

    private static func nonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Splits a byte stream into newline-terminated lines, keeping a partial trailing line
/// until the rest arrives. Used to read the helper's stdout chunk by chunk.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    /// Appends `chunk` and returns every complete line it finished, without newlines.
    public mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex ..< newline]
            pending = Data(pending[pending.index(after: newline)...])
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.hasSuffix("\r") ? String(line.dropLast()) : line)
            }
        }
        return lines
    }

    /// Whatever arrived after the last newline, if anything.
    public var partialLine: String? {
        guard !pending.isEmpty else { return nil }
        return String(data: pending, encoding: .utf8)
    }
}
