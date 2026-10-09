import Foundation

/// What a script's `render()` returns: elements laid out along the dock, and how soon to ask
/// again. The host draws it with the same views the built-in widgets use. The JSON form is
/// documented in `docs/scripted-widgets.md`.
public struct ScriptedTile: Equatable, Sendable {
    public var elements: [ScriptedElement]
    /// Seconds until the next render, as the script asked (`ScriptedRefreshPolicy` clamps it).
    public var refresh: Double?
    /// Least width along the dock, in icon widths, so a tile doesn't jitter as its text changes.
    public var minWidth: Double?
    /// What VoiceOver reads. `defaultAccessibilityLabel` is used when this is nil.
    public var accessibilityLabel: String?

    public init(
        elements: [ScriptedElement], refresh: Double? = nil, minWidth: Double? = nil, accessibilityLabel: String? = nil
    ) {
        self.elements = elements
        self.refresh = refresh
        self.minWidth = minWidth
        self.accessibilityLabel = accessibilityLabel
    }

    /// Decodes JSON from `render()` and checks it against `limits`.
    public static func decode(_ data: Data, limits: ScriptedWidgetLimits = .default) throws(ScriptedWidgetError)
        -> ScriptedTile
    {
        guard data.count <= limits.maxTileBytes else {
            throw .tileTooLarge(bytes: data.count, limit: limits.maxTileBytes)
        }
        let tile: ScriptedTile
        do {
            tile = try JSONDecoder().decode(ScriptedTile.self, from: data)
        } catch {
            throw .invalidTile(Self.describe(error))
        }
        try tile.check(limits)
        return tile
    }

    /// Every text in the tile, in order, for VoiceOver when the script gives no label.
    public var defaultAccessibilityLabel: String {
        elements.flatMap(\.texts).joined(separator: ", ")
    }

    /// The number of elements, nested ones included.
    public var elementCount: Int {
        elements.reduce(0) { $0 + $1.count }
    }

    /// How deeply rows and columns nest; an empty tile is 0, a flat one 1.
    public var depth: Int {
        elements.map(\.depth).max() ?? 0
    }

    private func check(_ limits: ScriptedWidgetLimits) throws(ScriptedWidgetError) {
        guard elementCount <= limits.maxElements else {
            throw .invalidTile("\(elementCount) elements; the most a tile may have is \(limits.maxElements)")
        }
        guard depth <= limits.maxDepth else {
            throw .invalidTile("rows and columns nest \(depth) deep; the most allowed is \(limits.maxDepth)")
        }
        for element in elements {
            try element.check(limits)
        }
        if let minWidth, !(0 ... limits.maxMinWidth).contains(minWidth) {
            throw .invalidTile("minWidth should be between 0 and \(Int(limits.maxMinWidth)) icon widths")
        }
    }

    static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath.reduce(into: "") { result, key in
                if let index = key.intValue {
                    result += "[\(index)]"
                } else {
                    result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return joined.isEmpty ? "the tile" : joined
        }
        switch decodingError {
        case let .keyNotFound(key, context):
            return "\(path(context)) is missing \"\(key.stringValue)\""
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            return "\(path(context)) has the wrong type"
        case let .dataCorrupted(context):
            return context.debugDescription.isEmpty ? "not valid JSON" : "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// One thing in a tile. Unknown kinds decode as `.unsupported` and draw nothing, so a script
/// written for a newer OpenDock degrades instead of failing.
public indirect enum ScriptedElement: Equatable, Sendable {
    case text(ScriptedText)
    case number(ScriptedNumber)
    case progress(ScriptedProgress)
    case icon(ScriptedIcon)
    case sparkline(ScriptedSparkline)
    case row(ScriptedGroup)
    case column(ScriptedGroup)
    case spacer
    case unsupported(String)

    /// This element and everything nested in it.
    public var count: Int {
        switch self {
        case let .row(group), let .column(group): return 1 + group.children.reduce(0) { $0 + $1.count }
        default: return 1
        }
    }

    var depth: Int {
        switch self {
        case let .row(group), let .column(group): return 1 + (group.children.map(\.depth).max() ?? 0)
        default: return 1
        }
    }

    var texts: [String] {
        switch self {
        case let .text(text): return [text.text]
        case let .number(number): return [number.label].compactMap { $0 }
        case let .progress(progress): return [progress.label].compactMap { $0 }
        case let .row(group), let .column(group): return group.children.flatMap(\.texts)
        case .icon, .sparkline, .spacer, .unsupported: return []
        }
    }

    func check(_ limits: ScriptedWidgetLimits) throws(ScriptedWidgetError) {
        switch self {
        case let .text(text):
            guard text.text.count <= limits.maxTextLength else {
                throw .invalidTile(
                    "a text is \(text.text.count) characters; the most allowed is \(limits.maxTextLength)")
            }
        case let .number(number):
            for string in [number.unit, number.label].compactMap({ $0 }) where string.count > limits.maxTextLength {
                throw .invalidTile("a label is \(string.count) characters; the most allowed is \(limits.maxTextLength)")
            }
        case let .progress(progress):
            if let label = progress.label, label.count > limits.maxTextLength {
                throw .invalidTile("a label is \(label.count) characters; the most allowed is \(limits.maxTextLength)")
            }
        case let .sparkline(sparkline):
            guard sparkline.samples.count <= limits.maxSparklineSamples else {
                throw .invalidTile(
                    "a sparkline has \(sparkline.samples.count) samples; the most allowed is \(limits.maxSparklineSamples)"
                )
            }
        case let .row(group), let .column(group):
            for child in group.children {
                try child.check(limits)
            }
        case .icon, .spacer, .unsupported:
            break
        }
    }
}

public struct ScriptedText: Equatable, Sendable {
    public var text: String
    public var style: ScriptedTextStyle
    public var color: ScriptedColor?

    public init(_ text: String, style: ScriptedTextStyle = .primary, color: ScriptedColor? = nil) {
        self.text = text
        self.style = style
        self.color = color
    }
}

/// A number the host formats for the user's locale, with an optional unit after it and a label
/// under it.
public struct ScriptedNumber: Equatable, Sendable {
    public var value: Double
    public var fractionDigits: Int?
    public var unit: String?
    public var label: String?
    public var color: ScriptedColor?

    public init(
        value: Double, fractionDigits: Int? = nil, unit: String? = nil, label: String? = nil,
        color: ScriptedColor? = nil
    ) {
        self.value = value
        self.fractionDigits = fractionDigits
        self.unit = unit
        self.label = label
        self.color = color
    }
}

/// A ring or a bar filled to `fraction` (0...1, clamped when drawn), with an optional label:
/// inside the ring, above the bar.
public struct ScriptedProgress: Equatable, Sendable {
    public var fraction: Double
    public var style: ScriptedProgressStyle
    public var color: ScriptedColor?
    public var label: String?

    public init(
        fraction: Double, style: ScriptedProgressStyle = .ring, color: ScriptedColor? = nil, label: String? = nil
    ) {
        self.fraction = fraction
        self.style = style
        self.color = color
        self.label = label
    }
}

/// An SF Symbol.
public struct ScriptedIcon: Equatable, Sendable {
    public var symbol: String
    public var color: ScriptedColor?
    public var size: ScriptedSize

    public init(symbol: String, color: ScriptedColor? = nil, size: ScriptedSize = .regular) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }
}

/// A line through 0...1 samples, oldest first, like the Network and System Activity tiles.
public struct ScriptedSparkline: Equatable, Sendable {
    public var samples: [Double]
    /// How many samples make a full chart; the sample count when nil.
    public var capacity: Int?
    public var color: ScriptedColor?

    public init(samples: [Double], capacity: Int? = nil, color: ScriptedColor? = nil) {
        self.samples = samples
        self.capacity = capacity
        self.color = color
    }
}

/// Children of a row or column. `spacing` is in icon widths.
public struct ScriptedGroup: Equatable, Sendable {
    public var children: [ScriptedElement]
    public var spacing: Double?
    public var alignment: ScriptedAlignment

    public init(children: [ScriptedElement], spacing: Double? = nil, alignment: ScriptedAlignment = .leading) {
        self.children = children
        self.spacing = spacing
        self.alignment = alignment
    }
}

public enum ScriptedTextStyle: String, Sendable, Codable {
    case primary
    case secondary
    case caption
}

public enum ScriptedProgressStyle: String, Sendable, Codable {
    case ring
    case bar
}

public enum ScriptedSize: String, Sendable, Codable {
    case small
    case regular
    case large
}

public enum ScriptedAlignment: String, Sendable, Codable {
    case leading
    case center
    case trailing
}

/// A system color by name, or `#RRGGBB`. Written as a string in JSON; a string that is neither
/// decodes as nil, so a typo means the default color rather than a broken tile.
public enum ScriptedColor: Equatable, Sendable {
    case named(ScriptedNamedColor)
    case hex(String)

    public init?(_ string: String) {
        if let named = ScriptedNamedColor(rawValue: string) {
            self = .named(named)
        } else if Self.isHex(string) {
            self = .hex(string.uppercased())
        } else {
            return nil
        }
    }

    private static func isHex(_ string: String) -> Bool {
        string.count == 7 && string.hasPrefix("#") && string.dropFirst().allSatisfy(\.isHexDigit)
    }
}

public enum ScriptedNamedColor: String, Sendable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case brown
    case gray
    case primary
    case secondary
}

// MARK: - Decoding

extension ScriptedTile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case elements
        case refresh
        case minWidth
        case accessibilityLabel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elements = try container.decodeIfPresent([ScriptedElement].self, forKey: .elements) ?? []
        refresh = try? container.decodeIfPresent(Double.self, forKey: .refresh)
        minWidth = try? container.decodeIfPresent(Double.self, forKey: .minWidth)
        accessibilityLabel = try? container.decodeIfPresent(String.self, forKey: .accessibilityLabel)
    }
}

extension ScriptedElement: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case style
        case color
        case value
        case fractionDigits
        case unit
        case label
        case fraction
        case symbol
        case size
        case samples
        case capacity
        case children
        case spacing
        case alignment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let color = (try? container.decodeIfPresent(String.self, forKey: .color)).flatMap(ScriptedColor.init)
        switch type {
        case "text":
            self = .text(
                ScriptedText(
                    try container.decode(String.self, forKey: .text),
                    style: Self.option(ScriptedTextStyle.self, container, .style) ?? .primary, color: color))
        case "number":
            self = .number(
                ScriptedNumber(
                    value: try container.decode(Double.self, forKey: .value),
                    fractionDigits: try? container.decodeIfPresent(Int.self, forKey: .fractionDigits),
                    unit: try? container.decodeIfPresent(String.self, forKey: .unit),
                    label: try? container.decodeIfPresent(String.self, forKey: .label), color: color))
        case "progress":
            self = .progress(
                ScriptedProgress(
                    fraction: try container.decode(Double.self, forKey: .fraction),
                    style: Self.option(ScriptedProgressStyle.self, container, .style) ?? .ring, color: color,
                    label: try? container.decodeIfPresent(String.self, forKey: .label)))
        case "icon":
            self = .icon(
                ScriptedIcon(
                    symbol: try container.decode(String.self, forKey: .symbol), color: color,
                    size: Self.option(ScriptedSize.self, container, .size) ?? .regular))
        case "sparkline":
            self = .sparkline(
                ScriptedSparkline(
                    samples: try container.decode([Double].self, forKey: .samples),
                    capacity: try? container.decodeIfPresent(Int.self, forKey: .capacity), color: color))
        case "row", "column":
            let group = ScriptedGroup(
                children: try container.decodeIfPresent([ScriptedElement].self, forKey: .children) ?? [],
                spacing: try? container.decodeIfPresent(Double.self, forKey: .spacing),
                alignment: Self.option(ScriptedAlignment.self, container, .alignment) ?? .leading)
            self = type == "row" ? .row(group) : .column(group)
        case "spacer":
            self = .spacer
        default:
            self = .unsupported(type)
        }
    }

    /// An optional enum field; a value that isn't one of the cases reads as nil (the default).
    private static func option<Option: RawRepresentable>(
        _: Option.Type, _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Option? where Option.RawValue == String {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return Option(rawValue: raw)
    }
}
