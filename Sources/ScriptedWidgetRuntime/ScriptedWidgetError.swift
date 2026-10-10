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
    /// `opendock.fetch` was pointed at a host the manifest doesn't list.
    case networkDenied(host: String)
    /// `opendock.fetch` failed: the URL, the network, the timeout, or the size cap.
    case fetchFailed(String)
    /// The storage file would pass `ScriptedWidgetLimits.maxStorageBytes`.
    case storageTooLarge(bytes: Int, limit: Int)
    /// The storage file is missing its shape, or couldn't be written.
    case storageUnreadable
    /// `opendock.settings.set` was given a key or a value the manifest doesn't allow.
    case invalidSetting(key: String, detail: String)
    /// `render()` was called before `load()` succeeded.
    case notLoaded
    /// The call was cancelled because the tile went away, not because the script failed.
    case cancelled
    /// JavaScriptCore isn't available in this build.
    case javaScriptUnavailable

    /// Which call the budget belonged to.
    public enum Phase: String, Sendable {
        case load
        case render
        case update
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
            let what: String
            switch phase {
            case .load: what = "Loading the script"
            case .render: what = "render()"
            case .update: what = "update()"
            }
            return "\(what) took longer than \(Self.seconds(limit)) and was stopped."
        case .missingRenderFunction:
            return "The script doesn't define a render() function."
        case let .invalidTile(detail):
            return "render() didn't return a tile: \(detail)"
        case let .tileTooLarge(bytes, limit):
            return "render() returned \(bytes) bytes of tile; the most allowed is \(limit)."
        case let .networkDenied(host):
            return "Can't contact \(host). Add it to permissions.network in manifest.json to allow it."
        case let .fetchFailed(detail):
            return detail.hasSuffix(".") ? detail : detail + "."
        case let .storageTooLarge(bytes, limit):
            return "Saving state would take \(bytes) bytes; the most a widget may store is \(limit)."
        case .storageUnreadable:
            return "The widget's saved state couldn't be read."
        case let .invalidSetting(key, detail):
            return key.isEmpty ? detail : "Setting \"\(key)\": \(detail)"
        case .notLoaded:
            return "The script hasn't been loaded."
        case .cancelled:
            return "The script was interrupted."
        case .javaScriptUnavailable:
            return "JavaScript isn't available in this build of OpenDock."
        }
    }

    /// What the tile says under the widget's name.
    public var shortDescription: String {
        switch self {
        case .unreadableFile, .manifest, .scriptTooLarge, .storageUnreadable: return "Can't load"
        case .exception, .missingRenderFunction, .invalidTile, .tileTooLarge, .invalidSetting: return "Script error"
        case .timedOut: return "Timed out"
        case let .networkDenied(host): return "Can't contact \(host)"
        case .fetchFailed: return "Can't fetch"
        case .storageTooLarge: return "Storage full"
        case .notLoaded: return "Loading…"
        case .cancelled: return "Loading…"
        case .javaScriptUnavailable: return "Unavailable"
        }
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        if interval >= 1, interval == interval.rounded() { return "\(Int(interval)) s" }
        return "\(Int((interval * 1000).rounded())) ms"
    }
}
