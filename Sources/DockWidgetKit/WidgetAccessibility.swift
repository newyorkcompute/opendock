import SwiftUI

/// A widget tile's name and state, spoken separately so VoiceOver can say
/// "Battery, 18 percent, low" instead of one undifferentiated string.
nonisolated public struct WidgetAccessibilityReading: Equatable, Sendable {
    /// The control's name, such as "Battery" or "Clock".
    public var label: String
    /// The state, such as "18 percent, low, 3:10 left". Empty when there is nothing to add.
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Spoken labels and values shared by widget tiles. Pure, so tests can lock the words;
/// `View.widgetAccessibility(_:)` applies a reading to a tile.
nonisolated public enum WidgetAccessibility: Sendable {
    /// Drops blank pieces and joins the rest with a comma.
    public static func phrase(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// `label` is the control's name. `value` is `parts` joined by `phrase`.
    public static func reading(_ label: String, value parts: [String]) -> WidgetAccessibilityReading {
        WidgetAccessibilityReading(label: label, value: phrase(parts))
    }

    /// "72 percent", or `unknown` when there is no reading.
    public static func percent(_ value: Int?, unknown: String = "unknown") -> String {
        guard let value else { return unknown }
        return "\(value) percent"
    }

    /// `fraction` is 0...1, rounded to the nearest percent. `unknown` when `fraction` is nil.
    public static func percent(fraction: Double?, unknown: String = "unknown") -> String {
        guard let fraction else { return unknown }
        return percent(Int((fraction * 100).rounded()), unknown: unknown)
    }

    /// A word for a battery percentage, matching the tile's green / yellow / red bands
    /// (`BatteryFormatting`: green from 50, yellow from 20, red below). Nil when there is
    /// no percentage. Charging paints the ring green at any level, so the word is what
    /// says a charging battery is still low.
    public static func chargeLevel(percent: Int?) -> String? {
        guard let percent else { return nil }
        if percent < 20 { return "low" }
        if percent < 50 { return "medium" }
        return "good"
    }
}

extension View {
    /// One accessibility element. `reading.label` is the name and `reading.value` is the
    /// state. `updatesFrequently` asks VoiceOver not to interrupt on every tick, for a
    /// clock that shows seconds.
    public func widgetAccessibility(
        _ reading: WidgetAccessibilityReading, updatesFrequently: Bool = false
    ) -> some View {
        modifier(WidgetAccessibilityModifier(reading: reading, updatesFrequently: updatesFrequently))
    }
}

private struct WidgetAccessibilityModifier: ViewModifier {
    var reading: WidgetAccessibilityReading
    var updatesFrequently: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.label)
            .accessibilityValue(reading.value)
            .accessibilityAddTraits(updatesFrequently ? .updatesFrequently : [])
    }
}
