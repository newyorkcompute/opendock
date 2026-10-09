import Foundation

/// One key a widget reads from `WidgetInstance.settings`. Values are stored as strings in
/// `dock.json`; `type` says which strings are allowed and how to read them.
public struct WidgetSettingKey: Hashable, Sendable, Identifiable {
    /// What a value for the key may look like.
    public enum ValueType: Hashable, Sendable {
        /// `"true"` or `"false"`.
        case bool
        /// Any string, including the empty string.
        case text
        /// One of the listed strings.
        case choice([String])
        /// A whole number within the range, written in decimal.
        case integer(ClosedRange<Int>)
        /// A number within the range, written in decimal with an optional fraction.
        case number(ClosedRange<Double>)
        /// An IANA time zone identifier such as `"Europe/Oslo"`, or `""` for the system zone.
        case timeZone

        /// Whether `value` is one of the strings this type describes, before a key's default
        /// is taken into account.
        public func accepts(_ value: String) -> Bool {
            switch self {
            case .bool:
                return value == "true" || value == "false"
            case .text:
                return true
            case let .choice(allowed):
                return allowed.contains(value)
            case let .integer(range):
                return Int(value).map(range.contains) ?? false
            case let .number(range):
                return Double(value).map { $0.isFinite && range.contains($0) } ?? false
            case .timeZone:
                return value.isEmpty || TimeZone(identifier: value) != nil
            }
        }
    }

    public var id: String { name }
    /// The key in the `settings` dictionary. Never rename one: it's in users' files.
    public let name: String
    public let type: ValueType
    /// Used when the key is missing or its value isn't valid for `type`. Always counts as
    /// valid itself, so an optional number or choice can default to `""` for "not set".
    public let defaultValue: String
    /// One sentence on what the key does, for `docs/widgets.md`.
    public let summary: String

    public init(_ name: String, type: ValueType, default defaultValue: String, summary: String) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.summary = summary
    }

    /// Whether `value` is something this key can hold: anything its type accepts, or its default.
    public func isValid(_ value: String) -> Bool {
        value == defaultValue || type.accepts(value)
    }

    /// The stored value when it's valid, otherwise the default.
    public func value(in settings: [String: String]) -> String {
        guard let stored = settings[name], isValid(stored) else { return defaultValue }
        return stored
    }

    /// `value(in:)` read as a boolean. Only meaningful for `.bool` keys.
    public func boolValue(in settings: [String: String]) -> Bool {
        value(in: settings) == "true"
    }

    /// `value(in:)` read as an integer, or the default when neither parses.
    public func intValue(in settings: [String: String]) -> Int {
        Int(value(in: settings)) ?? Int(defaultValue) ?? 0
    }

    /// `value(in:)` read as a number, or nil when it doesn't parse (an unset optional).
    public func doubleValue(in settings: [String: String]) -> Double? {
        Double(value(in: settings))
    }
}

/// Every settings key a widget type understands. Widgets declare one; the settings UI
/// reads through it, `DockStorage` validates against it when a file is loaded, and
/// `docs/widgets.md` is generated from it.
public struct WidgetSettingsSchema: Hashable, Sendable {
    public let keys: [WidgetSettingKey]

    public init(_ keys: [WidgetSettingKey] = []) {
        self.keys = keys
    }

    public var isEmpty: Bool { keys.isEmpty }

    public func key(named name: String) -> WidgetSettingKey? {
        keys.first { $0.name == name }
    }

    /// Settings for a freshly added instance: every key at its default.
    public var defaults: [String: String] {
        Dictionary(keys.map { ($0.name, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
    }

    /// Keys whose stored value isn't valid for the key.
    public func invalidKeys(in settings: [String: String]) -> [WidgetSettingKey] {
        keys.filter { key in settings[key.name].map { !key.isValid($0) } ?? false }
    }

    /// `settings` with every invalid value replaced by its key's default. Missing keys stay
    /// missing (they read as the default anyway), and keys the schema doesn't know are kept
    /// as they are, so a file written by a newer OpenDock survives a round trip.
    public func sanitized(_ settings: [String: String]) -> [String: String] {
        var result = settings
        for key in invalidKeys(in: settings) {
            result[key.name] = key.defaultValue
        }
        return result
    }
}
