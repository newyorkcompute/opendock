import DockCore
import DockWidgetKit
import SwiftUI

/// Settings for one sticky note: its paper color and the note itself. Reads the instance
/// it's given on each render rather than keeping a copy, so the editor's saves and the
/// color picker's never overwrite each other.
struct StickyNoteSettingsView: View {
    let instance: WidgetInstance

    @Environment(\.widgetUpdateSettings) private var updater

    private var settings: StickyNoteSettings { StickyNoteSettings(instance: instance) }

    var body: some View {
        Form {
            LabeledContent("Color") {
                StickyNoteColorPicker(selection: colorBinding)
            }

            LabeledContent("Note") {
                StickyNoteEditor(instance: instance, ink: .primary, minHeight: 90)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.background)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    )
            }
            Text("Click the tile in the dock to edit the note in a larger editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var colorBinding: Binding<StickyNoteColor> {
        Binding(
            get: { settings.color },
            set: { updater.set(StickyNoteSettings.color.name, to: $0.rawValue, in: instance) }
        )
    }
}
