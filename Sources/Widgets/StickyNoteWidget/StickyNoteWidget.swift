import DockCore
import DockWidgetKit
import SwiftUI

/// A note you type into the dock. The text and the paper color are the instance's
/// settings, so each tile is its own note and keeps it across launches. The tile shows
/// the first lines; clicking it opens an editor. The keys are declared in
/// `StickyNoteSettings` and listed in `docs/widgets.md`.
public enum StickyNoteWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.stickyNote
    public static let displayName = "Sticky Note"
    public static let systemImage = "note.text"
    public static let summary = "A note to yourself, on colored paper."
    public static let settingsSchema = StickyNoteSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(StickyNoteTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(StickyNotePopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(StickyNoteSettingsView(instance: instance))
    }
}

/// The sticky note's settings keys, and typed access to one instance's values.
struct StickyNoteSettings {
    static let text = WidgetSettingKey(
        "text", type: .text, default: "",
        summary:
            "The note itself, line breaks included. The tile shows its first few lines; the popover shows and edits all of it."
    )
    static let color = WidgetSettingKey(
        "color", type: .choice(StickyNoteColor.storageValues), default: StickyNoteColor.default.rawValue,
        summary:
            "The paper the note is written on. The colors and white take dark text, black takes white text, and translucent is the same surface as the other widgets."
    )

    static let schema = WidgetSettingsSchema([text, color])

    let instance: WidgetInstance

    var text: String { Self.text.value(in: instance.settings) }
    var color: StickyNoteColor { StickyNoteColor(storageValue: Self.color.value(in: instance.settings)) }
}
