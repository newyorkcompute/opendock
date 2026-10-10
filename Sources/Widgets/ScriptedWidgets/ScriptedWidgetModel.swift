import Foundation
import Observation
import ScriptedWidgetRuntime
import os

/// Drives one tile's script: loads it in a `ScriptedWidgetEngine`, calls `update()` when the
/// script defines one, renders on the schedule the script asks for, and publishes the tile or
/// the error for the view. Owned by the tile view as `@State`; `run` is called from its
/// `.task`, which SwiftUI cancels and restarts whenever the package, the settings, the edge
/// or the dock's visibility change.
@Observable
final class ScriptedWidgetModel {
    private(set) var tile: ScriptedTile?
    private(set) var error: ScriptedWidgetError?

    @ObservationIgnored private var engine: ScriptedWidgetEngine?
    @ObservationIgnored private var loaded: (id: String, revision: ScriptedWidgetPackage.Revision)?
    @ObservationIgnored private var rendered: (settings: [String: String], compact: Bool)?
    @ObservationIgnored private var lastRender: Date?
    @ObservationIgnored private var cachedDataJSON = "null"
    @ObservationIgnored private var hasUpdateHook = false
    @ObservationIgnored private let limits: ScriptedWidgetLimits

    nonisolated private static let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Scripted")

    init(limits: ScriptedWidgetLimits = .default) {
        self.limits = limits
    }

    /// Loads `package` if it isn't the one already running, then updates and renders until the
    /// task is cancelled. A script with `update()` is updated before each render, and `render`
    /// sees the cached result as `context.data`. Nothing runs while the dock is hidden. After
    /// an error the loop stops until something changes, so a bug can't spin. `persist` writes
    /// settings the script changed; that restarts this task with the new settings.
    func run(
        package: ScriptedWidgetPackage?, settings: [String: String], compact: Bool, visible: Bool,
        library: ScriptedWidgetLibrary?, persist: @escaping @MainActor ([String: String]) -> Void = { _ in }
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
            hasUpdateHook = await engine.definesUpdate
        }
        guard visible, let engine else { return }

        while !Task.isCancelled {
            let hasRendered = rendered != nil
            let settingsChanged = rendered.map { $0.settings != settings } ?? false
            let appearanceChanged = rendered.map { $0.compact != compact && $0.settings == settings } ?? false
            let refresh = ScriptedRefreshPolicy.interval(requested: tile?.refresh, limits: limits)
            let step = ScriptedUpdatePolicy.step(
                ScriptedUpdatePolicy.Input(
                    hasUpdateHook: hasUpdateHook, hasRendered: hasRendered, settingsChanged: settingsChanged,
                    appearanceChanged: appearanceChanged, lastRender: lastRender, refresh: hasRendered ? refresh : nil,
                    now: .now, visible: visible))
            let updateFirst: Bool
            switch step {
            case .idle:
                return
            case let .wait(delay):
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                }
                updateFirst = hasUpdateHook
            case .updateThenRender:
                updateFirst = true
            case .render:
                updateFirst = false
            }

            var effective = settings
            var pendingWrites: [String: String] = [:]
            if updateFirst {
                do {
                    let outcome = try await engine.update(
                        settings: effective, compact: compact, dataJSON: cachedDataJSON)
                    guard !Task.isCancelled else { return }
                    cachedDataJSON = outcome.value
                    pendingWrites = outcome.settingWrites
                    effective = Self.merging(pendingWrites, into: effective)
                } catch {
                    guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                    fail(error, in: library, package: package)
                    return
                }
            }
            do {
                let stopped = try await render(
                    engine: engine, settings: effective, compact: compact, library: library, package: package,
                    pendingWrites: pendingWrites, persist: persist)
                if stopped { return }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                fail(error, in: library, package: package)
                return
            }
        }
    }

    /// Renders and publishes the tile. Returns true when the script wrote settings, which
    /// restarts the loop via `persist`, so the caller should stop.
    private func render(
        engine: ScriptedWidgetEngine, settings: [String: String], compact: Bool, library: ScriptedWidgetLibrary?,
        package: ScriptedWidgetPackage, pendingWrites: [String: String],
        persist: @MainActor ([String: String]) -> Void
    ) async throws(ScriptedWidgetError) -> Bool {
        let outcome = try await engine.render(settings: settings, compact: compact, dataJSON: cachedDataJSON)
        guard !Task.isCancelled else { return true }
        tile = outcome.value
        error = nil
        var writes = pendingWrites
        for (key, value) in outcome.settingWrites { writes[key] = value }
        let merged = Self.merging(writes, into: settings)
        rendered = (merged, compact)
        lastRender = .now
        library?.report(nil, for: package.id)
        guard !writes.isEmpty else { return false }
        persist(writes)
        return true
    }

    private static func merging(_ writes: [String: String], into settings: [String: String]) -> [String: String] {
        var merged = settings
        for (key, value) in writes { merged[key] = value }
        return merged
    }

    private static func isCancellation(_ error: ScriptedWidgetError) -> Bool {
        if case .cancelled = error { return true }
        return false
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
        cachedDataJSON = "null"
        hasUpdateHook = false
        tile = nil
        error = nil
    }
}
