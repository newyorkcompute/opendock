import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock Now Playing tile: artwork, title and artist, plus transport buttons.
/// Takes no space while nothing is playing unless the instance asks to stay visible.
struct NowPlayingTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockIsVisible) private var isVisible
    @State private var monitor = NowPlayingMonitor.shared

    private var showControls: Bool { NowPlayingSettings.showControls(in: instance) }
    private var showWhenIdle: Bool { NowPlayingSettings.showWhenIdle(in: instance) }

    var body: some View {
        // A container that outlives the branches below, so switching between them doesn't
        // re-run onAppear/onDisappear and bounce the monitor's helper process.
        ZStack {
            if let track = monitor.track {
                WidgetTile {
                    HStack(spacing: iconSize * 0.16) {
                        NowPlayingArtworkView(image: monitor.artworkImage, size: iconSize * 0.74)
                        titles(for: track)
                        if showControls {
                            NowPlayingControls(isPlaying: track.isPlaying, size: iconSize * 0.3) { monitor.send($0) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel(for: track))
            } else if showWhenIdle {
                WidgetTile {
                    HStack(spacing: iconSize * 0.14) {
                        Image(systemName: "music.note")
                            .font(.system(size: iconSize * 0.36, weight: .semibold))
                            .foregroundStyle(.secondary)
                        WidgetSecondaryText("Nothing playing")
                    }
                }
                .accessibilityLabel("Now Playing: nothing playing")
            } else {
                Color.clear.frame(width: 0, height: iconSize)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
        .onChange(of: isVisible, initial: true) { _, visible in monitor.setDockVisible(visible) }
    }

    private func titles(for track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track.title)
                .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize) * 1.25, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            WidgetSecondaryText(NowPlayingFormatting.artistLine(for: track))
        }
        .frame(minWidth: iconSize * 1.3, maxWidth: iconSize * 2.8, alignment: .leading)
    }

    private func accessibilityLabel(for track: NowPlayingTrack) -> String {
        let state = track.isPlaying ? "Playing" : "Paused"
        return "\(state): \(track.title) by \(NowPlayingFormatting.artistLine(for: track))"
    }
}

/// Cover art in a rounded square, or a music note on a tinted square when there is none.
struct NowPlayingArtworkView: View {
    let image: NSImage?
    let size: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// Previous, play/pause and next. `size` is the play/pause glyph's point size; the skip
/// buttons are a little smaller.
struct NowPlayingControls: View {
    let isPlaying: Bool
    let size: Double
    let send: (NowPlayingCommand) -> Void

    var body: some View {
        HStack(spacing: size * 0.55) {
            button("backward.fill", size: size * 0.78, label: "Previous track") { send(.previousTrack) }
            button(isPlaying ? "pause.fill" : "play.fill", size: size, label: isPlaying ? "Pause" : "Play") {
                send(.togglePlayPause)
            }
            button("forward.fill", size: size * 0.78, label: "Next track") { send(.nextTrack) }
        }
    }

    private func button(_ symbol: String, size: Double, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: size * 1.6, height: size * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
    }
}
