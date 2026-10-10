import Foundation

/// A JSON value, so scripted-widget storage can cross actors without `Any`. Objects keep
/// their keys in insertion order; encoding sorts them, so a file's size doesn't depend on
/// the order a script wrote the keys.
public enum ScriptedJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ScriptedJSON])
    case object([String: ScriptedJSON])

    /// Parses one JSON value. Numbers that aren't finite, and anything that isn't JSON, are nil.
    public static func parse(_ data: Data) -> ScriptedJSON? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return convert(object)
    }

    public static func parse(_ string: String) -> ScriptedJSON? {
        parse(Data(string.utf8))
    }

    /// Compact JSON, with object keys sorted. `JSONSerialization` only writes arrays and
    /// objects, so a single value is wrapped in an array and the brackets are removed.
    public func encoded() throws -> Data {
        let wrapped = try JSONSerialization.data(withJSONObject: [foundationObject], options: [.sortedKeys])
        guard wrapped.count >= 2, wrapped.first == UInt8(ascii: "["), wrapped.last == UInt8(ascii: "]") else {
            throw ScriptedWidgetError.storageUnreadable
        }
        return Data(wrapped.dropFirst().dropLast())
    }

    public func encodedString() throws -> String {
        String(decoding: try encoded(), as: UTF8.self)
    }

    /// The Foundation object `JSONSerialization` wants. `null` is `NSNull`.
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .array(values): values.map(\.foundationObject)
        case let .object(values): values.mapValues(\.foundationObject)
        }
    }

    private static func convert(_ object: Any) -> ScriptedJSON? {
        if object is NSNull { return .null }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let value = number.doubleValue
            return value.isFinite ? .number(value) : nil
        }
        if let string = object as? String { return .string(string) }
        if let array = object as? [Any] {
            var values: [ScriptedJSON] = []
            for element in array {
                guard let value = convert(element) else { return nil }
                values.append(value)
            }
            return .array(values)
        }
        if let dictionary = object as? [String: Any] {
            var values: [String: ScriptedJSON] = [:]
            for (key, element) in dictionary {
                guard let value = convert(element) else { return nil }
                values[key] = value
            }
            return .object(values)
        }
        return nil
    }
}
