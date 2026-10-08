import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Detail view shown when the tile is clicked: big artwork, title, artist and album, a
/// position bar, transport controls and the player it all comes from.
struct NowPlayingPopoutView: View {
    @State private var monitor = NowPlayingMonitor.shared

    var body: some View {
        VStack(spacing: 14) {
            if let track = monitor.track {
                content(for: track)
            } else {
                idle
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    @ViewBuilder
    private func content(for track: NowPlayingTrack) -> some View {
        NowPlayingArtworkView(image: monitor.artworkImage, size: 180)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

        VStack(spacing: 3) {
            Text(track.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(NowPlayingFormatting.artistLine(for: track))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let album = track.album, !album.isEmpty, album != track.title {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }

        if track.duration != nil || track.elapsed != nil {
            TimelineView(.periodic(from: .now, by: track.isPlaying ? 1 : 3600)) { context in
                positionBar(for: track, at: context.date)
            }
        }

        NowPlayingControls(isPlaying: track.isPlaying, size: 22) { monitor.send($0) }
            .padding(.top, 2)

        Divider()

        HStack(spacing: 8) {
            if let app = monitor.playerApplication, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(monitor.playerName.map { "Playing in \($0)" } ?? "Now Playing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if monitor.playerApplication != nil {
                Button("Open") { monitor.activatePlayer() }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func positionBar(for track: NowPlayingTrack, at date: Date) -> some View {
        VStack(spacing: 4) {
            ProgressView(value: track.progress(at: date) ?? 0)
                .progressViewStyle(.linear)
                .tint(.primary.opacity(0.6))
            HStack {
                Text(track.elapsed(at: date).map(NowPlayingFormatting.time) ?? "--:--")
                Spacer()
                Text(NowPlayingFormatting.remaining(for: track, at: date) ?? "")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var idle: some View {
        Image(systemName: "music.note")
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 180, height: 120)
        Text("Nothing playing")
            .font(.headline)
        Text(idleCaption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var idleCaption: String {
        if monitor.isUnavailable {
            return "OpenDock can't read what's playing on this Mac."
        }
        if let source = monitor.sourceName {
            return "Start something in a media app and it shows up here, read from \(source)."
        }
        return "Start something in a media app and it shows up here."
    }
}
