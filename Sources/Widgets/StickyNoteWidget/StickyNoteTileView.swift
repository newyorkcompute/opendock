import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock note: the first lines of the text on its paper. A blank note shows a
/// placeholder so there is something to click.
struct StickyNoteTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    /// Width of the tile along the bottom edge, in icons. Fixed, so typing never
    /// changes the dock's layout.
    private static let widthInIcons = 2.6

    var body: some View {
        let settings = StickyNoteSettings(instance: instance)
        let color = settings.color
        let preview = StickyNoteText.preview(of: settings.text, maxLines: edge.isVertical ? 4 : 3)
        WidgetTile(fill: color.tileFill) {
            Group {
                if preview.isEmpty {
                    placeholder(color: color)
                } else {
                    Text(preview)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(color.inkColor)
                        .lineLimit(edge.isVertical ? 4 : 3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: contentWidth, alignment: .leading)
            .frame(maxWidth: edge.isVertical ? .infinity : nil, alignment: .leading)
            .padding(.vertical, edge.isVertical ? 0 : iconSize * 0.08)
        }
        .help(helpText(settings))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(settings))
    }

    private var fontSize: Double {
        max(10, iconSize * 0.21)
    }

    /// The text's width on the bottom edge; nil on a side edge, where the tile is an
    /// icon wide and `WidgetTile` sets the width.
    private var contentWidth: CGFloat? {
        guard !edge.isVertical else { return nil }
        return iconSize * Self.widthInIcons - 2 * WidgetMetrics.horizontalPadding(for: iconSize)
    }

    private func placeholder(color: StickyNoteColor) -> some View {
        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.04 : 0.1)) {
            Image(systemName: "note.text")
                .font(.system(size: iconSize * 0.3, weight: .medium))
            Text("New note")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(color.fadedInkColor)
    }

    private func helpText(_ settings: StickyNoteSettings) -> String {
        StickyNoteText.isBlank(settings.text) ? "Click to write a note" : StickyNoteText.firstLine(of: settings.text)
    }

    private func accessibilityLabel(_ settings: StickyNoteSettings) -> String {
        if StickyNoteText.isBlank(settings.text) {
            return "Sticky Note: empty, \(settings.color.displayName.lowercased()) paper"
        }
        return "Sticky Note: \(StickyNoteText.preview(of: settings.text))"
    }
}
