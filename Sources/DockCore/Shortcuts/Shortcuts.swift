import Foundation

/// The shortcuts on this Mac, as the `shortcuts` command-line tool lists them, and the
/// pure parts of picking one: parsing the tool's output and filtering by a search field.
public enum ShortcutsCatalog {
    /// The names in `shortcuts list` output: one per line, in the order the tool prints
    /// them (the Shortcuts app's order). Blank lines are dropped, surrounding whitespace is
    /// trimmed, and a name the tool prints twice appears once.
    public static func names(fromListOutput output: String) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for line in output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }

    /// `names` that contain `query`, ignoring case and diacritics. An empty or blank query
    /// matches everything. Names are kept in their original order.
    public static func filter(_ names: [String], matching query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return names }
        return names.filter { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// The shortcuts a tile ran last, stored in its `recents` setting as one name per line,
/// newest first.
public enum ShortcutHistory {
    /// How many names are kept.
    public static let limit = 8

    /// The names in a stored value, newest first. Blank lines are dropped.
    public static func names(from stored: String) -> [String] {
        ShortcutsCatalog.names(fromListOutput: stored)
    }

    /// The stored form of `names`: one per line.
    public static func stored(_ names: [String]) -> String {
        names.joined(separator: "\n")
    }

    /// `names` with `name` at the front (moved there if it was already in the list), cut
    /// to `limit`. A blank name leaves the list alone.
    public static func adding(_ name: String, to names: [String], limit: Int = ShortcutHistory.limit) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return names }
        var result = names.filter { $0 != trimmed }
        result.insert(trimmed, at: 0)
        return Array(result.prefix(max(0, limit)))
    }
}

/// Why `shortcuts run` didn't finish normally, from its exit status and what it printed.
public enum ShortcutRunFailure: Hashable, Sendable {
    /// No shortcut with that name exists (any more).
    case notFound
    /// The shortcut asked something and the user dismissed it, or stopped the shortcut.
    case cancelled
    /// The shortcut ran longer than OpenDock waits for it and was stopped.
    case timedOut
    /// The `shortcuts` tool isn't on this Mac or couldn't be started.
    case toolUnavailable
    /// Anything else, with the tool's own words when it printed any.
    case other(String)

    /// A short sentence for the tile and popover.
    public var message: String {
        switch self {
        case .notFound: "Shortcut not found"
        case .cancelled: "Cancelled"
        case .timedOut: "Timed out"
        case .toolUnavailable: "Shortcuts isn't available"
        case let .other(detail): detail.isEmpty ? "Failed" : detail
        }
    }

    /// Reads the tool's result: `nil` for a clean exit, otherwise the closest case. `standardError`
    /// is what the tool printed; its first line, minus an `Error:` prefix, becomes `other`'s text.
    public static func interpret(exitStatus: Int32, standardError: String, timedOut: Bool = false) -> Self? {
        if timedOut { return .timedOut }
        guard exitStatus != 0 else { return nil }
        let detail = firstMessageLine(in: standardError)
        let lowered = detail.lowercased()
        if lowered.contains("not found") || lowered.contains("no shortcut") || lowered.contains("couldn’t find")
            || lowered.contains("couldn't find")
        {
            return .notFound
        }
        if lowered.contains("cancel") { return .cancelled }
        return .other(detail.isEmpty ? "Failed (exit status \(exitStatus))" : detail)
    }

    /// The first non-blank line of `output` without a leading `Error:` or `error:`, so it
    /// reads as a sentence in the UI. Empty when the tool printed nothing useful.
    public static func firstMessageLine(in output: String) -> String {
        guard
            let line = output.split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty })
        else { return "" }
        let prefixes = ["Error:", "error:"]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}

/// What a shortcut is doing, or last did, as the tile and popover show it.
public enum ShortcutRunState: Hashable, Sendable {
    case running(since: Date)
    case succeeded(at: Date)
    case failed(ShortcutRunFailure, at: Date)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// When the run started or ended.
    public var date: Date {
        switch self {
        case let .running(since): since
        case let .succeeded(at), let .failed(_, at): at
        }
    }

    /// The failure, when there was one.
    public var failure: ShortcutRunFailure? {
        if case let .failed(failure, _) = self { return failure }
        return nil
    }

    /// A word or two for the tile's caption and the popover's status line.
    public var statusText: String {
        switch self {
        case .running: "Running…"
        case .succeeded: "Done"
        case let .failed(failure, _): failure.message
        }
    }
}

/// The Shortcuts app's URL scheme, for the few things the command-line tool can't do.
public enum ShortcutsURL {
    /// Opens the shortcut named `name` in the Shortcuts editor.
    public static func open(name: String) -> URL? {
        url(action: "open-shortcut", name: name)
    }

    /// Runs the shortcut named `name` in the Shortcuts app, which comes to the front. The
    /// command-line tool is quieter; this is the fallback for when it isn't available.
    public static func run(name: String) -> URL? {
        url(action: "run-shortcut", name: name)
    }

    /// Starts a new, empty shortcut in the Shortcuts editor.
    public static let create = URL(string: "shortcuts://create-shortcut")

    private static func url(action: String, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = action
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }
}

/// The colors a Shortcuts tile can take, named as the Shortcuts app's icon colors are.
public enum ShortcutTint: String, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    /// The tint a fresh tile gets.
    public static let `default` = ShortcutTint.indigo
}

/// SF Symbols offered for a Shortcuts tile's icon, in the order the settings show them.
/// Any other symbol name can be typed in; this list is just the quick picks.
public enum ShortcutSymbols {
    /// The icon a tile draws when its `symbol` setting is empty or isn't a symbol on this Mac.
    public static let `default` = "sparkles"

    public static let suggested: [String] = [
        "sparkles", "bolt.fill", "wand.and.stars", "play.fill", "star.fill", "heart.fill",
        "moon.fill", "sun.max.fill", "house.fill", "lightbulb.fill", "bell.fill", "clock.fill",
        "timer", "calendar", "doc.text.fill", "folder.fill", "tray.full.fill", "envelope.fill",
        "message.fill", "phone.fill", "music.note", "speaker.wave.2.fill", "headphones", "mic.fill",
        "camera.fill", "photo.fill", "video.fill", "display", "keyboard", "terminal.fill",
        "gearshape.fill", "lock.fill", "wifi", "globe", "link", "paperplane.fill",
        "square.and.arrow.up", "arrow.clockwise", "trash.fill", "scissors", "paintbrush.fill", "book.fill",
        "briefcase.fill", "cart.fill", "car.fill", "airplane", "figure.walk", "leaf.fill",
        "flame.fill", "drop.fill", "cup.and.saucer.fill", "fork.knife", "bed.double.fill", "gamecontroller.fill",
        "pawprint.fill", "checkmark.circle.fill", "xmark.circle.fill", "command", "power", "hourglass",
    ]
}
