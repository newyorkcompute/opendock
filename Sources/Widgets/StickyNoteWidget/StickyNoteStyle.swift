import DockCore
import DockWidgetKit
import SwiftUI

/// How a note's color is drawn: the paper, the ink that reads on it, and the swatches
/// that pick it.
extension StickyNoteColor {
    /// The paper as a SwiftUI color, or nil for the translucent note.
    var paper: Color? {
        fill.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// The tile's fill: the paper, or the dock's standard tile surface.
    var tileFill: AnyShapeStyle? {
        paper.map { AnyShapeStyle($0) }
    }

    /// Text on this paper. Fixed for the paper colors so a yellow note has dark writing in
    /// dark mode too; the translucent note follows the system like the other tiles.
    var inkColor: Color {
        switch ink {
        case .dark: Color(.sRGB, white: 0.13)
        case .light: Color(.sRGB, white: 0.96)
        case .adaptive: .primary
        }
    }

    /// Captions and placeholders on this paper.
    var fadedInkColor: Color {
        inkColor.opacity(0.55)
    }
}

/// A row of circles, one per color, with a ring around the chosen one.
struct StickyNoteColorPicker: View {
    @Binding var selection: StickyNoteColor
    /// What the ring and check mark are drawn in, so they show on whatever is behind the row.
    var ink: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(StickyNoteColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    StickyNoteSwatch(color: color, isSelected: color == selection, ink: ink)
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(color == selection ? AccessibilityTraits.isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paper color")
    }
}

/// One color in the picker: a filled circle, hatched for the translucent note.
struct StickyNoteSwatch: View {
    let color: StickyNoteColor
    let isSelected: Bool
    let ink: Color

    private let diameter = 18.0

    var body: some View {
        ZStack {
            if let paper = color.paper {
                Circle().fill(paper)
            } else {
                Circle().fill(.primary.opacity(0.1))
                Circle().strokeBorder(.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color.inkColor)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if isSelected {
                Circle().strokeBorder(ink, lineWidth: 1.5).padding(-2.5)
            }
        }
        .contentShape(Circle())
    }
}
