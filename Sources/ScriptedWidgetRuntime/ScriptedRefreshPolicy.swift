import Foundation

/// How the host turns a script's `refresh` into a schedule. Scripts have no timers; they ask to
/// be rendered again by returning `refresh` seconds from `render()`, and the host decides.
public enum ScriptedRefreshPolicy {
    /// The seconds to wait before rendering again, or nil when the script didn't ask for a refresh.
    /// A request that isn't a positive finite number counts as no request; the rest is clamped into
    /// `limits.refreshRange`.
    public static func interval(requested: Double?, limits: ScriptedWidgetLimits = .default) -> TimeInterval? {
        guard let requested, requested.isFinite, requested > 0 else { return nil }
        return min(max(requested, limits.refreshRange.lowerBound), limits.refreshRange.upperBound)
    }

    /// Seconds until the next render is due: 0 when it's due now (nothing rendered yet, or the
    /// interval has passed), the remaining time otherwise, and nil when nothing is scheduled
    /// because the last tile asked for no refresh.
    public static func delayUntilNextRender(
        lastRender: Date?, interval: TimeInterval?, now: Date = .now
    ) -> TimeInterval? {
        guard let lastRender else { return 0 }
        guard let interval else { return nil }
        return max(0, interval - now.timeIntervalSince(lastRender))
    }
}
