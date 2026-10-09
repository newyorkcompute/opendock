import Foundation

/// Everything that can go wrong with a scripted widget, from a folder that isn't a package to a
/// `render()` that threw. `description` is the full message for Settings and the log;
/// `shortDescription` is the word or two the tile shows.
public enum ScriptedWidgetError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `manifest.json` or the script couldn't be read. The string is the file's name.
    case unreadableFile(String, reason: String)
    /// `manifest.json` doesn't describe a widget this OpenDock can run.
    case manifest(ScriptedManifestError)
    /// The script is bigger than `ScriptedWidgetLimits.maxScriptBytes`.
    case scriptTooLarge(bytes: Int, limit: Int)
    /// The script threw, or evaluating it failed. `line` is the script line when JavaScriptCore
    /// knows it.
    case exception(message: String, line: Int?)
    /// The script ran past its CPU budget and was stopped.
    case timedOut(Phase, limit: TimeInterval)
    /// `main.js` ran but didn't define a `render` function.
    case missingRenderFunction
    /// `render()` returned something that isn't a tile. The string says what and where.
    case invalidTile(String)
    /// The tile description, as JSON, is bigger than `ScriptedWidgetLimits.maxTileBytes`.
    case tileTooLarge(bytes: Int, limit: Int)
    /// `render()` was called before `load()` succeeded.
    case notLoaded
    /// JavaScriptCore isn't available in this build.
    case javaScriptUnavailable

    /// Which call the budget belonged to.
    public enum Phase: String, Sendable {
        case load
        case render
    }

    public var description: String {
        switch self {
        case let .unreadableFile(name, reason):
            return "Couldn't read \(name): \(reason)"
        case let .manifest(error):
            return "manifest.json: \(error.description)"
        case let .scriptTooLarge(bytes, limit):
            return "The script is \(bytes) bytes; the most a widget may have is \(limit)."
        case let .exception(message, line):
            return line.map { "Line \($0): \(message)" } ?? message
        case let .timedOut(phase, limit):
            let what = phase == .load ? "Loading the script" : "render()"
            return "\(what) took longer than \(Self.seconds(limit)) and was stopped."
        case .missingRenderFunction:
            return "The script doesn't define a render() function."
        case let .invalidTile(detail):
            return "render() didn't return a tile: \(detail)"
        case let .tileTooLarge(bytes, limit):
            return "render() returned \(bytes) bytes of tile; the most allowed is \(limit)."
        case .notLoaded:
            return "The script hasn't been loaded."
        case .javaScriptUnavailable:
            return "JavaScript isn't available in this build of OpenDock."
        }
    }

    /// What the tile says under the widget's name.
    public var shortDescription: String {
        switch self {
        case .unreadableFile, .manifest, .scriptTooLarge: return "Can't load"
        case .exception, .missingRenderFunction, .invalidTile, .tileTooLarge: return "Script error"
        case .timedOut: return "Timed out"
        case .notLoaded: return "Loading…"
        case .javaScriptUnavailable: return "Unavailable"
        }
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        if interval >= 1, interval == interval.rounded() { return "\(Int(interval)) s" }
        return "\(Int((interval * 1000).rounded())) ms"
    }
}
