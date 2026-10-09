import DockCore
import SwiftUI

// Pieces for a widget's settings view and popover that every widget would otherwise
// write for itself.

/// A text field for a `.text` key. The value is saved on submit and when the view goes
/// away, not on every keystroke, so typing doesn't rewrite `dock.json` over and over.
///
/// ```swift
/// WidgetTextSetting("Label", key: ClockSettings.label, instance: $instance)
/// ```
public struct WidgetTextSetting: View {
    private let title: LocalizedStringKey
    private let key: WidgetSettingKey
    private let instance: Binding<WidgetInstance>
    private let prompt: Text?

    @Environment(\.widgetUpdateSettings) private var updater
    @State private var text: String

    /// - Parameters:
    ///   - title: The field's label.
    ///   - key: The `.text` key to edit.
    ///   - instance: The settings view's copy of the instance; the saved value is written
    ///     into it too.
    ///   - prompt: Placeholder shown while the field is empty.
    public init(
        _ title: LocalizedStringKey, key: WidgetSettingKey, instance: Binding<WidgetInstance>, prompt: Text? = nil
    ) {
        self.title = title
        self.key = key
        self.instance = instance
        self.prompt = prompt
        _text = State(initialValue: key.value(in: instance.wrappedValue.settings))
    }

    public var body: some View {
        TextField(title, text: $text, prompt: prompt)
            .onSubmit(commit)
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard text != key.value(in: instance.wrappedValue.settings) else { return }
        instance.wrappedValue.settings[key.name] = text
        updater(instance.wrappedValue)
    }
}

/// Secondary explanatory text: a footnote under a settings control, or a detail line in
/// a popover.
public struct WidgetCaption: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
