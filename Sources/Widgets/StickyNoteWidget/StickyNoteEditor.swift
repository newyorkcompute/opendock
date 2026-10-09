import DockCore
import DockWidgetKit
import SwiftUI

/// The text editor shared by the popover and the Settings window. It keeps its own copy of
/// the text and writes it through the updater a moment after typing stops, and when it
/// goes away, so a note isn't saved to disk on every keystroke.
struct StickyNoteEditor: View {
    let instance: WidgetInstance
    let ink: Color
    let font: Font
    let minHeight: CGFloat
    /// Whether the editor takes the keyboard as soon as it appears, as it does in the popover.
    let focusesOnAppear: Bool

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var text: String
    /// What was last written through the updater (or read from the instance), so a
    /// change made elsewhere can be told apart from this editor's own writes coming back.
    @State private var committed: String
    @State private var pendingCommit: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    /// How long after the last keystroke the note is saved.
    private static let commitDelay: Duration = .milliseconds(400)

    init(
        instance: WidgetInstance, ink: Color, font: Font = .body, minHeight: CGFloat = 120,
        focusesOnAppear: Bool = false
    ) {
        self.instance = instance
        self.ink = ink
        self.font = font
        self.minHeight = minHeight
        self.focusesOnAppear = focusesOnAppear
        let stored = StickyNoteSettings.text.value(in: instance.settings)
        _text = State(initialValue: stored)
        _committed = State(initialValue: stored)
    }

    var body: some View {
        let stored = StickyNoteSettings.text.value(in: instance.settings)
        TextEditor(text: $text)
            .font(font)
            .foregroundStyle(ink)
            .tint(ink)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: minHeight)
            .accessibilityLabel("Note")
            .onChange(of: text) { scheduleCommit() }
            .onChange(of: stored) { _, newValue in
                // Edited in the other place (Settings while the popover is open, or the
                // other way round), or imported: show that, unless it's our own write.
                guard newValue != committed else { return }
                pendingCommit?.cancel()
                text = newValue
                committed = newValue
            }
            .onAppear {
                guard focusesOnAppear else { return }
                // The popover's window isn't key yet when the content appears.
                Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    isFocused = true
                }
            }
            .onDisappear {
                pendingCommit?.cancel()
                commit()
            }
    }

    private func scheduleCommit() {
        pendingCommit?.cancel()
        pendingCommit = Task {
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        let value = StickyNoteText.storageValue(for: text)
        guard value != committed else { return }
        committed = value
        updater.set(StickyNoteSettings.text.name, to: value, in: instance)
    }
}
