import Foundation

/// What the host allows a scripted widget: how long its script may run, how big its files and
/// its tile description may be, and how often it may ask to be redrawn. One value, so tests can
/// tighten the limits and a developer mode could loosen them.
public struct ScriptedWidgetLimits: Equatable, Sendable {
    /// CPU seconds `main.js` may take to evaluate.
    public var loadTimeout: TimeInterval = 2
    /// CPU seconds one `render()` call may take.
    public var renderTimeout: TimeInterval = 0.25
    /// Wall-clock seconds one `update()` may take, including the fetches it waits on.
    public var updateTimeout: TimeInterval = 10
    /// CPU seconds of JavaScript one `update()` may run between awaits.
    public var updateCPUTimeout: TimeInterval = 2
    /// Seconds one `opendock.fetch` may take.
    public var fetchTimeout: TimeInterval = 10
    /// Largest fetch request or response body, in bytes.
    public var maxFetchBytes: Int = 1_048_576
    /// Most fetches one widget may have in flight.
    public var maxInFlightFetches: Int = 4
    /// Most redirects one fetch may follow. One that leaves the allow-list is an error, not a hop.
    public var maxRedirects: Int = 5
    /// Largest per-widget storage file, in bytes.
    public var maxStorageBytes: Int = 262_144
    /// Largest package, archive or folder, in bytes. Stops a mistaken drop, not an attacker.
    public var maxPackageBytes: Int = 20_971_520
    /// Seconds between renders a script may ask for; requests outside are clamped.
    public var refreshRange: ClosedRange<TimeInterval> = 1 ... 3600
    /// Largest `main.js`, in bytes.
    public var maxScriptBytes: Int = 1_048_576
    /// Largest tile description, as JSON, in bytes.
    public var maxTileBytes: Int = 65536
    /// Most elements in one tile, nested ones included.
    public var maxElements: Int = 64
    /// Deepest nesting of rows and columns; the top level is depth 1.
    public var maxDepth: Int = 4
    /// Longest text in one element, in characters.
    public var maxTextLength: Int = 200
    /// Most samples in one sparkline.
    public var maxSparklineSamples: Int = 256
    /// Widest tile a script may ask for, in icon widths.
    public var maxMinWidth: Double = 8

    public init() {}

    public static let `default` = ScriptedWidgetLimits()
}
