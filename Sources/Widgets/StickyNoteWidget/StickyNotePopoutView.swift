import DockCore
import DockWidgetKit
import SwiftUI

/// Shown when the tile is clicked: the whole note in an editor on its paper, the color
/// swatches, and a word count.
struct StickyNotePopoutView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater

    private var settings: StickyNoteSettings { StickyNoteSettings(instance: instance) }

    var body: some View {
        let settings = self.settings
        let color = settings.color
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StickyNoteColorPicker(selection: colorBinding, ink: color.inkColor)
                Spacer()
                Button("Clear") {
                    updater.set(StickyNoteSettings.text.name, to: "", in: instance)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(color.fadedInkColor)
                .disabled(StickyNoteText.isBlank(settings.text))
            }

            StickyNoteEditor(
                instance: instance, ink: color.inkColor, font: .system(size: 14), minHeight: 170,
                focusesOnAppear: true)

            Text(StickyNoteText.countSummary(settings.text))
                .font(.caption)
                .foregroundStyle(color.fadedInkColor)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(color.paper ?? .clear)
    }

    private var colorBinding: Binding<StickyNoteColor> {
        Binding(
            get: { settings.color },
            set: { updater.set(StickyNoteSettings.color.name, to: $0.rawValue, in: instance) }
        )
    }
}
