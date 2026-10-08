import DockCore
import Foundation

/// Renders the generated part of `docs/widgets.md` from the widgets' settings schemas.
/// Only depends on `DockCore`, so the same code can run anywhere the models compile.
enum WidgetDocs {
    /// One widget, as the docs describe it.
    struct Entry {
        let typeID: String
        let displayName: String
        let summary: String
        let schema: WidgetSettingsSchema
    }

    static let beginMarker = "<!-- BEGIN GENERATED (make widget-docs) -->"
    static let endMarker = "<!-- END GENERATED -->"

    /// The text between the markers, markers included, ending in a newline.
    static func generatedSection(for entries: [Entry]) -> String {
        var lines = [beginMarker, ""]
        for entry in entries {
            lines.append("## \(entry.displayName)")
            lines.append("")
            lines.append("Type ID: `\(entry.typeID)`")
            lines.append("")
            lines.append(entry.summary)
            lines.append("")
            if entry.schema.isEmpty {
                lines.append("This widget has no settings.")
            } else {
                lines.append("| Key | Value | Default | What it does |")
                lines.append("| --- | --- | --- | --- |")
                for key in entry.schema.keys {
                    lines.append(
                        "| `\(key.name)` | \(describe(key.type)) | \(quoted(key.defaultValue)) | \(key.summary) |")
                }
            }
            lines.append("")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `document` with the text between the markers replaced by `section`, or nil when
    /// the markers are missing or out of order.
    static func replacingGeneratedSection(in document: String, with section: String) -> String? {
        guard let begin = document.range(of: beginMarker),
            let end = document.range(of: endMarker, range: begin.upperBound ..< document.endIndex)
        else { return nil }
        var result = document
        let sectionWithoutTrailingNewline = section.hasSuffix("\n") ? String(section.dropLast()) : section
        result.replaceSubrange(begin.lowerBound ..< end.upperBound, with: sectionWithoutTrailingNewline)
        return result
    }

    /// The text between the markers, markers included, as it is in `document`.
    static func generatedSection(in document: String) -> String? {
        guard let begin = document.range(of: beginMarker),
            let end = document.range(of: endMarker, range: begin.upperBound ..< document.endIndex)
        else { return nil }
        return String(document[begin.lowerBound ..< end.upperBound]) + "\n"
    }

    static func describe(_ type: WidgetSettingKey.ValueType) -> String {
        switch type {
        case .bool:
            return "`\"true\"` or `\"false\"`"
        case .text:
            return "Any text"
        case let .choice(values):
            let quotedValues = values.map(quoted)
            switch quotedValues.count {
            case 0, 1:
                return "One of " + quotedValues.joined()
            case 2:
                return "One of \(quotedValues[0]) or \(quotedValues[1])"
            default:
                return "One of " + quotedValues.dropLast().joined(separator: ", ") + ", or "
                    + quotedValues[quotedValues.count - 1]
            }
        case let .integer(range):
            return "A whole number from \(range.lowerBound) to \(range.upperBound)"
        case let .number(range):
            return "A number from \(formatted(range.lowerBound)) to \(formatted(range.upperBound))"
        case .timeZone:
            return "An IANA time zone name such as `\"Europe/Oslo\"`, or `\"\"` for the Mac's time zone"
        }
    }

    static func quoted(_ value: String) -> String {
        "`\"\(value)\"`"
    }

    /// `-90` rather than `-90.0` for whole numbers, independent of the locale.
    static func formatted(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
