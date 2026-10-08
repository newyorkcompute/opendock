import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock Now Playing tile: artwork, title and artist, plus transport buttons, in a
/// row on the bottom edge and stacked on a side edge. Takes no space while nothing is
/// playing unless the instance asks to stay visible.
struct NowPlayingTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @State private var monitor = NowPlayingMonitor.shared

    /// Text beside the artwork on the bottom edge, under it on a side edge.
    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    private var showControls: Bool { NowPlayingSettings.showControls.boolValue(in: instance.settings) }
    private var showWhenIdle: Bool { NowPlayingSettings.showWhenIdle.boolValue(in: instance.settings) }

    var body: some View {
        // A container that outlives the branches below, so switching between them doesn't
        // re-run onAppear/onDisappear and bounce the monitor's helper process.
        ZStack {
            if let track = monitor.track {
                WidgetTile {
                    WidgetStack(spacing: iconSize * (edge.isVertical ? 0.1 : 0.16)) {
                        NowPlayingArtworkView(
                            image: monitor.artworkImage,
                            size: iconSize * (edge.isVertical ? 0.84 : 0.74))
                        titles(for: track)
                        if showControls {
                            NowPlayingControls(
                                isPlaying: track.isPlaying,
                                size: iconSize * (edge.isVertical ? 0.2 : 0.3),
                                compact: edge.isVertical
                            ) { monitor.send($0) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel(for: track))
            } else if showWhenIdle {
                WidgetTile {
                    WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
                        Image(systemName: "music.note")
                            .font(.system(size: iconSize * 0.36, weight: .semibold))
                            .foregroundStyle(.secondary)
                        WidgetSecondaryText(edge.isVertical ? "Idle" : "Nothing playing")
                    }
                }
                .accessibilityLabel("Now Playing: nothing playing")
            } else if edge.isVertical {
                Color.clear.frame(width: iconSize, height: 0)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 0, height: iconSize)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
        .onChange(of: isVisible, initial: true) { _, visible in monitor.setDockVisible(visible) }
    }

    @ViewBuilder
    private func titles(for track: NowPlayingTrack) -> some View {
        let stack = VStack(alignment: textAlignment, spacing: 1) {
            Text(track.title)
                .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize) * 1.25, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(edge.isVertical ? 0.7 : 1)
            WidgetSecondaryText(NowPlayingFormatting.artistLine(for: track))
        }
        if edge.isVertical {
            stack.frame(maxWidth: .infinity)
        } else {
            stack.frame(minWidth: iconSize * 1.3, maxWidth: iconSize * 2.8, alignment: .leading)
        }
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
/// buttons are a little smaller. `compact` tightens the spacing and hit areas so the three
/// buttons fit in a tile that is only an icon wide (on a side edge).
struct NowPlayingControls: View {
    let isPlaying: Bool
    let size: Double
    var compact = false
    let send: (NowPlayingCommand) -> Void

    var body: some View {
        HStack(spacing: size * (compact ? 0.3 : 0.55)) {
            button("backward.fill", size: size * 0.78, label: "Previous track") { send(.previousTrack) }
            button(isPlaying ? "pause.fill" : "play.fill", size: size, label: isPlaying ? "Pause" : "Play") {
                send(.togglePlayPause)
            }
            button("forward.fill", size: size * 0.78, label: "Next track") { send(.nextTrack) }
        }
    }

    private func button(_ symbol: String, size: Double, label: String, action: @escaping () -> Void) -> some View {
        let hitSize = size * (compact ? 1.25 : 1.6)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
    }
}
