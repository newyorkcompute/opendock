import Foundation

/// Turns a value a script passed to `opendock.settings.set` into the string `dock.json`
/// stores, or refuses it. The type has to match the manifest (`bool` for a bool, a number
/// for an integer or number, a string otherwise); nothing is coerced.
public enum ScriptedSettingsWrite {
    public enum Input: Equatable, Sendable {
        case bool(Bool)
        case number(Double)
        case string(String)
    }

    /// The string to store for `key`, when `input` is valid for the manifest.
    public static func storedString(
        _ input: Input, for key: String, in manifest: ScriptedWidgetManifest
    ) throws(ScriptedWidgetError) -> String {
        guard let definition = manifest.settings.first(where: { $0.key.name == key }) else {
            throw .invalidSetting(key: key, detail: "there is no setting named \"\(key)\".")
        }
        let setting = definition.key
        let stored: String
        switch (setting.type, input) {
        case (.bool, .bool(let value)):
            stored = value ? "true" : "false"
        case (.integer, .number(let value)):
            guard value.isFinite, value == value.rounded(), abs(value) < 1e15 else {
                throw .invalidSetting(key: key, detail: "it needs a whole number.")
            }
            stored = String(Int(value))
        case (.number, .number(let value)):
            guard value.isFinite else { throw .invalidSetting(key: key, detail: "it needs a finite number.") }
            stored = decimal(value)
        case (.text, .string(let value)), (.choice, .string(let value)), (.timeZone, .string(let value)):
            stored = value
        default:
            throw .invalidSetting(key: key, detail: "the value's type doesn't match the setting.")
        }
        guard setting.isValid(stored) else {
            throw .invalidSetting(key: key, detail: "\"\(stored)\" isn't valid for it.")
        }
        return stored
    }

    /// A number as `dock.json` stores it: a whole number without a fraction, otherwise the
    /// shortest decimal `Double` prints.
    static func decimal(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }
}
