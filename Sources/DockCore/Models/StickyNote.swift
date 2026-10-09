import Foundation

/// The backgrounds a sticky note can have. Raw values are stored in `dock.json` as the
/// widget's `color` setting, so they never change.
public enum StickyNoteColor: String, CaseIterable, Sendable {
    case yellow
    case orange
    case pink
    case green
    case blue
    case purple
    case white
    case black
    /// The dock's standard tile surface, so the note looks like the other widgets.
    case translucent

    public static let `default`: StickyNoteColor = .yellow

    /// A stored value, or the default when the value isn't a color we know.
    public init(storageValue: String) {
        self = StickyNoteColor(rawValue: storageValue) ?? .default
    }

    /// The raw values, for the widget's settings schema and its docs.
    public static var storageValues: [String] { allCases.map(\.rawValue) }

    /// Shown in the settings picker and read out by VoiceOver.
    public var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .pink: "Pink"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .white: "White"
        case .black: "Black"
        case .translucent: "Translucent"
        }
    }

    /// The fill, in sRGB, or nil for the translucent note, which uses the tile's own surface.
    /// The paper colors are light enough for dark text in both appearances.
    public var fill: StickyNoteRGB? {
        switch self {
        case .yellow: StickyNoteRGB(red: 1.0, green: 0.88, blue: 0.40)
        case .orange: StickyNoteRGB(red: 1.0, green: 0.73, blue: 0.47)
        case .pink: StickyNoteRGB(red: 1.0, green: 0.70, blue: 0.80)
        case .green: StickyNoteRGB(red: 0.70, green: 0.92, blue: 0.62)
        case .blue: StickyNoteRGB(red: 0.64, green: 0.84, blue: 1.0)
        case .purple: StickyNoteRGB(red: 0.85, green: 0.76, blue: 1.0)
        case .white: StickyNoteRGB(red: 0.98, green: 0.98, blue: 0.97)
        case .black: StickyNoteRGB(red: 0.11, green: 0.11, blue: 0.12)
        case .translucent: nil
        }
    }

    /// The text color that reads on this background.
    public var ink: StickyNoteInk {
        switch self {
        case .black: .light
        case .translucent: .adaptive
        default: .dark
        }
    }
}

/// An sRGB color with components from 0 to 1. `DockCore` has no SwiftUI, so this is what
/// the widget turns into a `Color`.
public struct StickyNoteRGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Which text color a note's background calls for.
public enum StickyNoteInk: Sendable {
    /// Near-black text, for the paper colors and white.
    case dark
    /// White text, for black.
    case light
    /// The system's primary text color, for the translucent note.
    case adaptive
}

/// What a sticky note shows of its text: the stored form, the tile's preview, and the counts
/// in the editor's footer.
public enum StickyNoteText {
    /// Longer notes are cut when stored; `dock.json` is loaded on every launch and the tile
    /// has room for a few lines, not a document.
    public static let maximumLength = 10_000

    /// How much of the note the tile shows at most.
    public static let previewLines = 3
    public static let previewLength = 160

    /// `text` as it's stored: line endings normalized to `\n` and no longer than
    /// `maximumLength`. Whitespace is kept, so the editor and the file agree character for
    /// character.
    public static func storageValue(for text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return String(normalized.prefix(maximumLength))
    }

    /// True when the note has nothing but whitespace in it.
    public static func isBlank(_ text: String) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }

    /// The first `maxLines` non-blank lines of the note, each trimmed, cut to `maxLength`
    /// characters in all, with an ellipsis when anything was left out. Empty for a blank note.
    public static func preview(of text: String, maxLines: Int = previewLines, maxLength: Int = previewLength)
        -> String
    {
        let lines = nonBlankLines(of: text)
        guard !lines.isEmpty, maxLines > 0, maxLength > 0 else { return "" }
        var truncated = lines.count > maxLines
        var joined = lines.prefix(maxLines).joined(separator: "\n")
        if joined.count > maxLength {
            joined = String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            truncated = true
        }
        return truncated ? joined + "…" : joined
    }

    /// The first non-blank line, trimmed, for the tile's accessibility label and tooltips.
    public static func firstLine(of text: String) -> String {
        nonBlankLines(of: text).first ?? ""
    }

    /// How many words the note has, counting runs of non-whitespace.
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// "3 words" or "1 word", plus the character count when it's long enough to matter.
    public static func countSummary(_ text: String) -> String {
        let words = wordCount(text)
        let characters = text.count
        let wordText = words == 1 ? "1 word" : "\(words) words"
        if characters >= maximumLength {
            return "\(wordText) · \(characters) characters (limit)"
        }
        return characters < 100 ? wordText : "\(wordText) · \(characters) characters"
    }

    /// The note's lines without leading or trailing whitespace, blank lines dropped.
    private static func nonBlankLines(of text: String) -> [String] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
