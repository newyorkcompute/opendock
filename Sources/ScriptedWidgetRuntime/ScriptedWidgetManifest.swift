import DockCore
import Foundation

/// `manifest.json`: what a scripted widget is called, which JS API it speaks, the settings it
/// reads, and what it's allowed to do. Decoding ignores keys it doesn't know, so a manifest
/// written for a newer OpenDock still loads here as long as its `apiVersion` is one we run;
/// what it does read is validated strictly, with an error that names the field.
public struct ScriptedWidgetManifest: Equatable, Sendable {
    /// The JS API versions this OpenDock can run (see `docs/scripted-widgets.md`).
    public static let supportedAPIVersions: Set<Int> = [1]
    /// The version new widgets should declare.
    public static let currentAPIVersion = 1
    /// Settings keys the host owns in a scripted tile's settings; a manifest may not declare them.
    public static let reservedSettingKeys: Set<String> = ["package"]
    /// Ids under OpenDock's own namespace are for built-in widgets.
    public static let reservedIDPrefix = "com.newyorkcompute.opendock."

    public var apiVersion: Int
    /// Reverse-DNS identifier, stored in users' `dock.json`. Never changes once published.
    public var id: String
    public var name: String
    public var version: String
    public var summary: String
    /// SF Symbol for the picker and the placeholder tile.
    public var symbol: String
    /// The script's path, relative to the package folder.
    public var main: String
    public var author: String?
    public var homepage: String?
    public var settings: [ScriptedSettingDefinition]
    public var permissions: ScriptedPermissions

    public init(
        apiVersion: Int = ScriptedWidgetManifest.currentAPIVersion, id: String, name: String, version: String,
        summary: String, symbol: String = "curlybraces", main: String = "main.js", author: String? = nil,
        homepage: String? = nil, settings: [ScriptedSettingDefinition] = [], permissions: ScriptedPermissions = .none
    ) {
        self.apiVersion = apiVersion
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
        self.symbol = symbol
        self.main = main
        self.author = author
        self.homepage = homepage
        self.settings = settings
        self.permissions = permissions
    }

    /// The settings as the rest of OpenDock sees them: validation, bindings, and docs all work
    /// on this, exactly as for a built-in widget.
    public var settingsSchema: WidgetSettingsSchema {
        WidgetSettingsSchema(settings.map(\.key))
    }

    /// Decodes and validates `manifest.json`.
    public static func decode(_ data: Data) throws(ScriptedWidgetError) -> ScriptedWidgetManifest {
        let raw: RawManifest
        do {
            raw = try JSONDecoder().decode(RawManifest.self, from: data)
        } catch {
            throw .manifest(.malformed(Self.describe(error)))
        }
        do {
            return try ScriptedWidgetManifest(validating: raw)
        } catch {
            throw .manifest(error)
        }
    }

    /// Checks the rules every manifest must follow. The initializer above trusts its caller.
    public func validate() throws(ScriptedManifestError) {
        guard Self.supportedAPIVersions.contains(apiVersion) else {
            throw .unsupportedAPIVersion(apiVersion)
        }
        guard Self.isValidID(id) else { throw .invalidID(id) }
        guard !id.hasPrefix(Self.reservedIDPrefix) else { throw .reservedID(id) }
        for (field, value) in [("name", name), ("version", version), ("summary", summary)]
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .missingField(field)
        }
        guard Self.isValidRelativePath(main) else { throw .invalidMainPath(main) }

        var seen: Set<String> = []
        for definition in settings {
            let key = definition.key
            guard Self.isValidSettingKey(key.name) else { throw .invalidSettingKey(key.name) }
            guard !Self.reservedSettingKeys.contains(key.name) else { throw .reservedSettingKey(key.name) }
            guard seen.insert(key.name).inserted else { throw .duplicateSettingKey(key.name) }
            if case let .choice(choices) = key.type, choices.isEmpty { throw .emptyChoices(key: key.name) }
            // A key's own default always passes `isValid`, so the type is asked directly. An
            // empty default is allowed as "not set" for everything but a bool, as the Weather
            // widget's coordinates use it.
            guard key.type.accepts(key.defaultValue) || (key.defaultValue.isEmpty && key.type != .bool) else {
                throw .invalidDefault(key: key.name, value: key.defaultValue)
            }
            guard !key.summary.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw .missingSummary(key: key.name)
            }
        }
        for host in permissions.networkHosts {
            guard ScriptedHostAllowList.isValidPattern(host) else { throw .invalidHostPattern(host) }
        }
    }

    // MARK: Settings for the script

    /// The settings as `render()` receives them: every declared key, read through its schema key
    /// (so an invalid stored value is the default), and typed the way JavaScript wants it.
    public func scriptSettings(from settings: [String: String]) -> [String: ScriptedSettingValue] {
        var result: [String: ScriptedSettingValue] = [:]
        for definition in self.settings {
            let key = definition.key
            let stored = key.value(in: settings)
            switch key.type {
            case .bool:
                result[key.name] = .bool(stored == "true")
            case .integer, .number:
                result[key.name] = Double(stored).map(ScriptedSettingValue.number) ?? .string(stored)
            case .text, .choice, .timeZone:
                result[key.name] = .string(stored)
            }
        }
        return result
    }

    // MARK: Rules

    /// Reverse-DNS-ish: letters, digits, dots, hyphens and underscores, 3 to 100 characters, with
    /// at least one dot that isn't at either end or doubled.
    public static func isValidID(_ id: String) -> Bool {
        guard (3 ... 100).contains(id.count), id.contains("."), !id.hasPrefix("."), !id.hasSuffix("."),
            !id.contains("..")
        else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_")
        }
    }

    /// The same rule `WidgetSchemaTests` applies to built-in widgets: a lowerCamelCase identifier.
    public static func isValidSettingKey(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase, first.isLetter else { return false }
        return name.allSatisfy { ($0.isLetter || $0.isNumber) && $0.isASCII }
    }

    /// Inside the package only: not absolute, no `..` components, no empty path.
    public static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0 == ".." || $0.isEmpty }
    }

    /// "refreshSeconds" as "Refresh seconds", for a setting without a `title`.
    public static func defaultTitle(forKey key: String) -> String {
        var words: [String] = []
        var current = ""
        for character in key {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case let .keyNotFound(key, _): return "missing \"\(key.stringValue)\""
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\"\(path)\" has the wrong type"
        case let .dataCorrupted(context):
            return context.debugDescription.isEmpty ? "not valid JSON" : context.debugDescription
        @unknown default: return error.localizedDescription
        }
    }
}

/// One entry of a manifest's `settings`: a `WidgetSettingKey` plus the label Settings shows.
public struct ScriptedSettingDefinition: Equatable, Sendable, Identifiable {
    public var id: String { key.name }
    public var key: WidgetSettingKey
    public var title: String

    public init(key: WidgetSettingKey, title: String? = nil) {
        self.key = key
        self.title = title ?? ScriptedWidgetManifest.defaultTitle(forKey: key.name)
    }
}

/// A setting's value as JavaScript receives it.
public enum ScriptedSettingValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)

    /// The value as a JSON-compatible Foundation object, for handing to JavaScriptCore.
    public var jsonObject: Any {
        switch self {
        case let .bool(value): return value
        case let .number(value): return value
        case let .string(value): return value
        }
    }
}

/// What a manifest declares its script may do beyond rendering. The host only installs
/// `opendock.fetch` when `network` lists at least one host. `openURL` and `shortcuts` are
/// accepted in the manifest and shown to the user; the functions aren't installed yet.
public struct ScriptedPermissions: Equatable, Sendable {
    /// Hosts `opendock.fetch` may contact: exact names, or one leading `*.` label. Empty means
    /// no network.
    public var networkHosts: [String]
    /// Whether `opendock.openURL` is available.
    public var openURL: Bool
    /// Which shortcuts `opendock.runShortcut` may run: nil for none, empty for any.
    public var shortcuts: [String]?

    public init(networkHosts: [String] = [], openURL: Bool = false, shortcuts: [String]? = nil) {
        self.networkHosts = networkHosts
        self.openURL = openURL
        self.shortcuts = shortcuts
    }

    public static let none = ScriptedPermissions()

    public var isEmpty: Bool { networkHosts.isEmpty && !openURL && shortcuts == nil }

    /// What the permissions amount to, in words, for Settings and an install sheet.
    public var summary: [String] {
        var lines: [String] = []
        if !networkHosts.isEmpty { lines.append("Can contact \(networkHosts.joined(separator: ", "))") }
        if openURL { lines.append("Can open links when clicked") }
        if let shortcuts {
            lines.append(shortcuts.isEmpty ? "Can run any shortcut" : "Can run \(shortcuts.joined(separator: ", "))")
        }
        return lines
    }
}

/// Why a manifest was refused. Messages name the field so an author can fix it.
public enum ScriptedManifestError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformed(String)
    case unsupportedAPIVersion(Int)
    case invalidID(String)
    case reservedID(String)
    case missingField(String)
    case invalidMainPath(String)
    case invalidSettingKey(String)
    case reservedSettingKey(String)
    case duplicateSettingKey(String)
    case invalidSettingType(key: String, type: String)
    case invalidSettingRange(key: String)
    case emptyChoices(key: String)
    case invalidDefault(key: String, value: String)
    case missingSummary(key: String)
    case unknownPermission(String)
    case invalidPermission(String)
    case invalidHostPattern(String)

    public var description: String {
        switch self {
        case let .malformed(detail):
            return "couldn't be read (\(detail))."
        case let .unsupportedAPIVersion(version):
            let supported = ScriptedWidgetManifest.supportedAPIVersions.sorted().map(String.init).joined(
                separator: ", ")
            return "apiVersion \(version) isn't supported by this OpenDock (it runs \(supported))."
                + (version > ScriptedWidgetManifest.currentAPIVersion ? " Update OpenDock." : "")
        case let .invalidID(id):
            return "\"\(id)\" isn't a valid id. Use reverse-DNS form such as \"com.example.hello\"."
        case let .reservedID(id):
            return "\"\(id)\" is in OpenDock's own namespace; pick an id of your own."
        case let .missingField(field):
            return "\"\(field)\" is missing or empty."
        case let .invalidMainPath(path):
            return "\"main\" must be a path inside the package, not \"\(path)\"."
        case let .invalidSettingKey(key):
            return "setting \"\(key)\" should be a lowerCamelCase identifier, such as \"showRing\"."
        case let .reservedSettingKey(key):
            return "setting \"\(key)\" is a name OpenDock uses itself; pick another."
        case let .duplicateSettingKey(key):
            return "setting \"\(key)\" is declared twice."
        case let .invalidSettingType(key, type):
            return "setting \"\(key)\" has unknown type \"\(type)\"."
                + " Use bool, text, choice, integer, number, or timeZone."
        case let .invalidSettingRange(key):
            return "setting \"\(key)\" needs \"min\" and \"max\" (whole numbers for integer), with min ≤ max."
        case let .emptyChoices(key):
            return "setting \"\(key)\" needs a non-empty \"choices\" list."
        case let .invalidDefault(key, value):
            return "setting \"\(key)\" has default \"\(value)\", which isn't valid for its type."
        case let .missingSummary(key):
            return "setting \"\(key)\" needs a one-sentence \"summary\"."
        case let .unknownPermission(name):
            return "permission \"\(name)\" isn't one this OpenDock knows (network, openURL, shortcuts)."
        case let .invalidPermission(name):
            return "permission \"\(name)\" has the wrong shape; see docs/scripted-widgets.md."
        case let .invalidHostPattern(pattern):
            return "permission \"network\" lists \"\(pattern)\", which isn't a host or a *.domain pattern."
        }
    }
}

// MARK: - Raw JSON

/// The manifest as JSON, before validation. Everything optional so the error can say what's
/// missing instead of "keyNotFound".
struct RawManifest: Decodable {
    var apiVersion: Int?
    var id: String?
    var name: String?
    var version: String?
    var summary: String?
    var symbol: String?
    var main: String?
    var author: String?
    var homepage: String?
    var settings: [RawSetting]?
    var permissions: [String: RawPermissionValue]?

    struct RawSetting: Decodable {
        var key: String?
        var title: String?
        var type: String?
        var choices: [String]?
        var min: Double?
        var max: Double?
        var `default`: JSONScalar?
        var summary: String?
    }

    /// `true`, or a list of strings, depending on the permission.
    enum RawPermissionValue: Decodable {
        case flag(Bool)
        case list([String])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else {
                self = .list(try container.decode([String].self))
            }
        }
    }
}

/// A JSON string, number or boolean, read as the string `dock.json` stores.
enum JSONScalar: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String {
        switch self {
        case let .string(value): return value
        case let .bool(value): return value ? "true" : "false"
        case let .number(value):
            return value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
        }
    }
}

extension ScriptedWidgetManifest {
    init(validating raw: RawManifest) throws(ScriptedManifestError) {
        guard let apiVersion = raw.apiVersion else { throw .missingField("apiVersion") }
        guard let id = raw.id else { throw .missingField("id") }
        guard let name = raw.name else { throw .missingField("name") }
        guard let version = raw.version else { throw .missingField("version") }
        guard let summary = raw.summary else { throw .missingField("summary") }

        var settings: [ScriptedSettingDefinition] = []
        for rawSetting in raw.settings ?? [] {
            settings.append(try ScriptedSettingDefinition(validating: rawSetting))
        }

        var permissions = ScriptedPermissions.none
        for (permissionName, value) in (raw.permissions ?? [:]).sorted(by: { $0.key < $1.key }) {
            switch (permissionName, value) {
            case let ("network", .list(hosts)):
                permissions.networkHosts = hosts
            case ("openURL", .flag(let flag)):
                permissions.openURL = flag
            case ("shortcuts", .flag(let flag)):
                permissions.shortcuts = flag ? [] : nil
            case let ("shortcuts", .list(names)):
                permissions.shortcuts = names
            case ("network", .flag), ("openURL", .list):
                throw .invalidPermission(permissionName)
            default:
                throw .unknownPermission(permissionName)
            }
        }

        self.init(
            apiVersion: apiVersion, id: id, name: name, version: version, summary: summary,
            symbol: raw.symbol ?? "curlybraces", main: raw.main ?? "main.js", author: raw.author,
            homepage: raw.homepage, settings: settings, permissions: permissions)
        try validate()
    }
}

extension ScriptedSettingDefinition {
    init(validating raw: RawManifest.RawSetting) throws(ScriptedManifestError) {
        guard let name = raw.key, !name.isEmpty else { throw .missingField("settings[].key") }
        guard let typeName = raw.type else { throw .invalidSettingType(key: name, type: "") }
        let type: WidgetSettingKey.ValueType
        switch typeName {
        case "bool": type = .bool
        case "text": type = .text
        case "timeZone": type = .timeZone
        case "choice": type = .choice(raw.choices ?? [])
        case "integer":
            guard let min = raw.min, let max = raw.max, min <= max, min == min.rounded(), max == max.rounded(),
                abs(min) < 1e15, abs(max) < 1e15
            else { throw .invalidSettingRange(key: name) }
            type = .integer(Int(min) ... Int(max))
        case "number":
            guard let min = raw.min, let max = raw.max, min <= max, min.isFinite, max.isFinite else {
                throw .invalidSettingRange(key: name)
            }
            type = .number(min ... max)
        default:
            throw .invalidSettingType(key: name, type: typeName)
        }
        let key = WidgetSettingKey(
            name, type: type, default: raw.default?.stringValue ?? "", summary: raw.summary ?? "")
        self.init(key: key, title: raw.title)
    }
}
