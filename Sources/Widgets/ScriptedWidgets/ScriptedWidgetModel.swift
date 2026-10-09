import Foundation
import Observation
import ScriptedWidgetRuntime
import os

/// Drives one tile's script: loads it in a `ScriptedWidgetEngine`, renders on the schedule the
/// script asks for, and publishes the tile or the error for the view. Owned by the tile view
/// as `@State`; `run` is called from its `.task`, which SwiftUI cancels and restarts whenever
/// the package, the settings, the edge or the dock's visibility change.
@Observable
final class ScriptedWidgetModel {
    private(set) var tile: ScriptedTile?
    private(set) var error: ScriptedWidgetError?

    @ObservationIgnored private var engine: ScriptedWidgetEngine?
    @ObservationIgnored private var loaded: (id: String, revision: ScriptedWidgetPackage.Revision)?
    @ObservationIgnored private var rendered: (settings: [String: String], compact: Bool)?
    @ObservationIgnored private var lastRender: Date?
    @ObservationIgnored private let limits: ScriptedWidgetLimits

    nonisolated private static let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Scripted")

    init(limits: ScriptedWidgetLimits = .default) {
        self.limits = limits
    }

    /// Loads `package` if it isn't the one already running, then renders until the task is
    /// cancelled: now if anything changed, and again after each `refresh`. Nothing renders
    /// while the dock is hidden; the next `run` with `visible` renders right away. After an
    /// error the loop stops until something changes, so a bug can't spin.
    func run(
        package: ScriptedWidgetPackage?, settings: [String: String], compact: Bool, visible: Bool,
        library: ScriptedWidgetLibrary?
    ) async {
        guard let package else {
            reset()
            return
        }
        if loaded?.id != package.id || loaded?.revision != package.revision {
            reset()
            let engine = ScriptedWidgetEngine(package: package, limits: limits) { line in
                Self.log.info("\(line, privacy: .public)")
            }
            do {
                try await engine.load()
            } catch {
                fail(error, in: library, package: package)
                return
            }
            guard !Task.isCancelled else { return }
            self.engine = engine
            loaded = (package.id, package.revision)
        }
        guard visible, let engine else { return }

        var renderNow = tile == nil || rendered?.settings != settings || rendered?.compact != compact
        while !Task.isCancelled {
            if !renderNow {
                let interval = ScriptedRefreshPolicy.interval(requested: tile?.refresh, limits: limits)
                guard let delay = ScriptedRefreshPolicy.delayUntilNextRender(lastRender: lastRender, interval: interval)
                else { return }
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                }
            }
            renderNow = false
            do {
                let tile = try await engine.render(settings: settings, compact: compact)
                guard !Task.isCancelled else { return }
                self.tile = tile
                self.error = nil
                rendered = (settings, compact)
                lastRender = .now
                library?.report(nil, for: package.id)
            } catch {
                fail(error, in: library, package: package)
                return
            }
        }
    }

    private func fail(_ error: ScriptedWidgetError, in library: ScriptedWidgetLibrary?, package: ScriptedWidgetPackage)
    {
        guard !Task.isCancelled else { return }
        self.error = error
        library?.report(error, for: package.id)
    }

    private func reset() {
        engine = nil
        loaded = nil
        rendered = nil
        lastRender = nil
        tile = nil
        error = nil
    }
}
