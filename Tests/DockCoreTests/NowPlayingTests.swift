import Foundation
import Testing

@testable import DockCore

private let epoch = Date(timeIntervalSince1970: 1_760_000_000)

@Suite("Now Playing track")
struct NowPlayingTrackTests {
    @Test func extrapolatesThePositionWhilePlaying() {
        let track = NowPlayingTrack(title: "Song", duration: 200, elapsed: 30, timestamp: epoch, isPlaying: true)
        #expect(track.elapsed(at: epoch) == 30)
        #expect(track.elapsed(at: epoch.addingTimeInterval(12.5)) == 42.5)
        #expect(track.progress(at: epoch.addingTimeInterval(70)) == 0.5)
    }

    @Test func holdsThePositionWhilePaused() {
        let track = NowPlayingTrack(title: "Song", duration: 200, elapsed: 30, timestamp: epoch, isPlaying: false)
        #expect(track.elapsed(at: epoch.addingTimeInterval(60)) == 30)
        #expect(track.playbackRate == 0)
    }

    @Test func clampsToTheDurationAndNeverGoesBackwards() {
        let track = NowPlayingTrack(title: "Song", duration: 100, elapsed: 90, timestamp: epoch, isPlaying: true)
        #expect(track.elapsed(at: epoch.addingTimeInterval(500)) == 100)
        #expect(track.elapsed(at: epoch.addingTimeInterval(-500)) == 90)
        #expect(track.progress(at: epoch.addingTimeInterval(500)) == 1)
    }

    @Test func noPositionWithoutOne() {
        let track = NowPlayingTrack(title: "Live stream", isPlaying: true)
        #expect(track.elapsed(at: epoch) == nil)
        #expect(track.progress(at: epoch) == nil)
    }

    @Test func identityIgnoresPlaybackState() {
        let playing = NowPlayingTrack(title: "Song", artist: "Band", elapsed: 1, isPlaying: true)
        let paused = NowPlayingTrack(title: "Song", artist: "Band", elapsed: 50, isPlaying: false)
        #expect(playing.itemIdentity == paused.itemIdentity)
        #expect(playing != paused)
    }
}

@Suite("Now Playing formatting")
struct NowPlayingFormattingTests {
    @Test func formatsTimes() {
        #expect(NowPlayingFormatting.time(7) == "0:07")
        #expect(NowPlayingFormatting.time(185.9) == "3:05")
        #expect(NowPlayingFormatting.time(3753) == "1:02:33")
        #expect(NowPlayingFormatting.time(-4) == "0:00")
    }

    @Test func formatsTimeRemaining() {
        let track = NowPlayingTrack(title: "Song", duration: 200, elapsed: 30, timestamp: epoch, isPlaying: true)
        #expect(NowPlayingFormatting.remaining(for: track, at: epoch.addingTimeInterval(10)) == "-2:40")
        #expect(NowPlayingFormatting.remaining(for: NowPlayingTrack(title: "Radio", isPlaying: true), at: epoch) == nil)
    }

    @Test func fallsBackWhenTheArtistIsMissing() {
        #expect(
            NowPlayingFormatting.artistLine(for: NowPlayingTrack(title: "Song", artist: "  ", isPlaying: true))
                == "Unknown Artist")
        #expect(
            NowPlayingFormatting.artistLine(for: NowPlayingTrack(title: "Song", artist: "Band", isPlaying: true))
                == "Band")
    }

    @Test func namesPlayersFromBundleIDs() {
        #expect(NowPlayingFormatting.playerName(forBundleID: "com.apple.Music") == "Music")
        #expect(NowPlayingFormatting.playerName(forBundleID: "com.spotify.client") == "Spotify")
        #expect(NowPlayingFormatting.playerName(forBundleID: "com.example.tunes") == "Tunes")
    }
}

@Suite("Now Playing arbiter")
struct NowPlayingArbiterTests {
    private func track(_ title: String, playing: Bool, at offset: TimeInterval) -> NowPlayingTrack {
        NowPlayingTrack(title: title, timestamp: epoch.addingTimeInterval(offset), isPlaying: playing)
    }

    @Test func theOnlyPlayingTrackWins() {
        let chosen = NowPlayingArbiter.choose(from: [
            track("paused, newer", playing: false, at: 100), track("playing, older", playing: true, at: 0),
        ])
        #expect(chosen?.title == "playing, older")
    }

    @Test func tiesGoToTheMostRecentUpdate() {
        let bothPaused = NowPlayingArbiter.choose(from: [
            track("older", playing: false, at: 0), track("newer", playing: false, at: 5),
        ])
        #expect(bothPaused?.title == "newer")
        let bothPlaying = NowPlayingArbiter.choose(from: [
            track("newer", playing: true, at: 5), track("older", playing: true, at: 0),
        ])
        #expect(bothPlaying?.title == "newer")
    }

    @Test func nothingFromNothing() {
        #expect(NowPlayingArbiter.choose(from: []) == nil)
    }
}

@Suite("Now Playing helper messages")
struct NowPlayingHelperMessageTests {
    private let artworkBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    private var fullLine: String {
        """
        {"kind":"nowPlaying","pid":512,"bundleIdentifier":"com.spotify.client","playing":true,"title":"Song",\
        "artist":"Band","album":"Album","duration":241.5,"elapsed":12.25,"timestamp":1760000000.5,"rate":1,\
        "hasArtwork":true,"artworkData":"\(artworkBytes.base64EncodedString())","artworkMimeType":"image/jpeg"}
        """
    }

    @Test func decodesAFullMessage() throws {
        let message = try #require(NowPlayingHelperMessage.parse(line: fullLine))
        #expect(message.kind == .nowPlaying)
        let track = try #require(message.track(previous: nil))
        #expect(track.title == "Song")
        #expect(track.artist == "Band")
        #expect(track.album == "Album")
        #expect(track.duration == 241.5)
        #expect(track.elapsed == 12.25)
        #expect(track.timestamp == Date(timeIntervalSince1970: 1_760_000_000.5))
        #expect(track.isPlaying)
        #expect(track.playbackRate == 1)
        #expect(track.playerPID == 512)
        #expect(track.playerBundleID == "com.spotify.client")
        #expect(track.artwork == NowPlayingArtwork(data: artworkBytes, mimeType: "image/jpeg"))
    }

    @Test func idleAndNoiseProduceNoTrack() {
        #expect(NowPlayingHelperMessage.parse(line: "{\"kind\":\"idle\"}")?.track(previous: nil) == nil)
        #expect(NowPlayingHelperMessage.parse(line: "") == nil)
        #expect(NowPlayingHelperMessage.parse(line: "Use of uninitialized value in perl") == nil)
        #expect(NowPlayingHelperMessage.parse(line: "{not json") == nil)
        #expect(NowPlayingHelperMessage.parse(line: "{\"kind\":\"nowPlaying\",\"pid\":1}")?.track(previous: nil) == nil)
    }

    @Test func keepsArtworkTheHelperDidNotResend() throws {
        let first = try #require(NowPlayingHelperMessage.parse(line: fullLine)?.track(previous: nil))
        let paused = try #require(
            NowPlayingHelperMessage.parse(
                line: "{\"kind\":\"nowPlaying\",\"pid\":512,\"playing\":false,\"title\":\"Song\",\"hasArtwork\":true}"
            )?.track(previous: first))
        #expect(paused.artwork == first.artwork)
        #expect(!paused.isPlaying)
        #expect(paused.playbackRate == 0)
        #expect(paused.playerBundleID == "com.spotify.client", "the bundle ID carries over for the same pid")
    }

    @Test func dropsArtworkWhenTheHelperSaysThereIsNone() throws {
        let first = try #require(NowPlayingHelperMessage.parse(line: fullLine)?.track(previous: nil))
        let next = try #require(
            NowPlayingHelperMessage.parse(
                line: "{\"kind\":\"nowPlaying\",\"pid\":700,\"playing\":true,\"title\":\"Other\",\"hasArtwork\":false}"
            )?.track(previous: first))
        #expect(next.artwork == nil)
        #expect(next.playerBundleID == nil, "a different pid is a different player")
    }

    @Test func infersPlayingFromTheRate() throws {
        let track = try #require(
            NowPlayingHelperMessage.parse(line: "{\"kind\":\"nowPlaying\",\"pid\":1,\"title\":\"Song\",\"rate\":1}")?
                .track(previous: nil))
        #expect(track.isPlaying)
    }
}

@Suite("Scripted players")
struct ScriptedPlayerTests {
    private let sep = String(ScriptedPlayer.fieldSeparator)

    @Test func parsesAMusicStatusLine() throws {
        let line = ["playing", "Song", "Band", "Album", "241500", "12250", "ABCDEF0123456789"].joined(separator: sep)
        let status = try #require(ScriptedPlayer.music.parseStatus(line + "\n", now: epoch))
        #expect(status.track.title == "Song")
        #expect(status.track.artist == "Band")
        #expect(status.track.album == "Album")
        #expect(status.track.duration == 241.5)
        #expect(status.track.elapsed == 12.25)
        #expect(status.track.timestamp == epoch)
        #expect(status.track.isPlaying)
        #expect(status.track.playerBundleID == "com.apple.Music")
        #expect(status.artworkReference == "ABCDEF0123456789")
    }

    @Test func parsesAPausedSpotifyLineWithMissingFields() throws {
        let line = ["paused", "Song", "", "", "", "", "https://i.scdn.co/image/abc"].joined(separator: sep)
        let status = try #require(ScriptedPlayer.spotify.parseStatus(line, now: epoch))
        #expect(!status.track.isPlaying)
        #expect(status.track.artist == nil)
        #expect(status.track.album == nil)
        #expect(status.track.duration == nil)
        #expect(status.track.elapsed == nil)
        #expect(status.artworkReference == "https://i.scdn.co/image/abc")
    }

    @Test func stoppedAndMalformedOutputMeanNothingIsPlaying() {
        #expect(ScriptedPlayer.music.parseStatus("stopped\n") == nil)
        #expect(ScriptedPlayer.music.parseStatus("") == nil)
        #expect(ScriptedPlayer.music.parseStatus("playing\(sep)Song") == nil)
        #expect(ScriptedPlayer.music.parseStatus(["playing", " ", "", "", "", "", ""].joined(separator: sep)) == nil)
    }

    @Test func scriptsTargetTheRightAppAndUnits() {
        #expect(ScriptedPlayer.music.statusScript.contains("tell application id \"com.apple.Music\""))
        #expect(ScriptedPlayer.music.statusScript.contains("(duration of t) * 1000"), "Music reports seconds")
        #expect(ScriptedPlayer.spotify.statusScript.contains("tell application id \"com.spotify.client\""))
        #expect(!ScriptedPlayer.spotify.statusScript.contains("(duration of t) * 1000"), "Spotify reports milliseconds")
        #expect(ScriptedPlayer.spotify.statusScript.contains("artwork url of t"))
        #expect(ScriptedPlayer.music.statusScript.contains("persistent ID of t"))
    }

    @Test func commandScripts() {
        #expect(
            ScriptedPlayer.music.script(for: .togglePlayPause) == "tell application id \"com.apple.Music\" to playpause"
        )
        #expect(
            ScriptedPlayer.spotify.script(for: .nextTrack) == "tell application id \"com.spotify.client\" to next track"
        )
        #expect(ScriptedPlayer.spotify.script(for: .previousTrack).hasSuffix("previous track"))
        #expect(ScriptedPlayer.music.script(for: .play).hasSuffix(" to play"))
        #expect(ScriptedPlayer.music.script(for: .pause).hasSuffix(" to pause"))
    }

    @Test func onlyMusicNeedsAnArtworkScript() {
        let script = ScriptedPlayer.music.artworkScript(writingTo: "/tmp/art \"quoted\"")
        #expect(script?.contains("POSIX file \"/tmp/art \\\"quoted\\\"\"") == true)
        #expect(ScriptedPlayer.spotify.artworkScript(writingTo: "/tmp/art") == nil)
    }
}

@Suite("Line buffer")
struct LineBufferTests {
    @Test func splitsLinesAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":1}\n{\"b\"".utf8)) == ["{\"a\":1}"])
        #expect(buffer.partialLine == "{\"b\"")
        #expect(buffer.append(Data(":2}\r\n\n".utf8)) == ["{\"b\":2}", ""])
        #expect(buffer.partialLine == nil)
    }

    @Test func emptyChunksProduceNothing() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data()).isEmpty)
        #expect(buffer.partialLine == nil)
    }
}
