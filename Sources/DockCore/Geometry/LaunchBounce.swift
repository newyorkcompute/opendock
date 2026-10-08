import Foundation

/// How an app's icon bounces while the app launches, as in Apple's Dock: it hops up and
/// falls back under gravity, hop after hop, until the app has finished launching. The hop
/// in the air at that moment is completed, so the icon always lands rather than dropping
/// mid-flight, and it makes at least one hop however quickly the app comes up. An app that
/// never reports finishing stops bouncing after `timeout`.
///
/// Pure timing, no UI, so it can be unit tested. The dock samples it every frame while an
/// icon bounces.
public struct LaunchBounce: Hashable, Sendable {
    /// One hop, up and back down. Apple's Dock takes about 0.65 s on current macOS.
    public static let hopDuration: TimeInterval = 0.65
    /// Height of a hop as a share of the icon's height as drawn, so a magnified icon
    /// bounces higher, like in Apple's Dock.
    public static let hopHeight = 0.5
    /// The longest an icon bounces for an app that never reports finishing its launch.
    public static let timeout: TimeInterval = 20
    /// With Reduce Motion the icon stays put and fades by up to this much in time with the
    /// hops instead.
    public static let reducedMotionFade = 0.4

    /// The most hops a launch gets: enough to cover `timeout`.
    public static var maximumHops: Int { hops(in: timeout) }

    /// How far above its resting place the top of a hop is, for an icon drawn
    /// `iconHeight` tall.
    public static func peakOffset(iconHeight: Double) -> Double {
        hopHeight * iconHeight
    }

    public let start: Date
    /// When the app finished launching, failed to, or quit; nil while it's still launching.
    public private(set) var launchEnd: Date?

    public init(start: Date, launchEnd: Date? = nil) {
        self.start = start
        self.launchEnd = launchEnd.map { max($0, start) }
    }

    /// Record that the launch is over. Only the first report counts.
    public mutating func launchEnded(at date: Date) {
        guard launchEnd == nil else { return }
        launchEnd = max(date, start)
    }

    /// Hops the icon makes in all, as far as is known now: up to the one in the air when
    /// the launch ended, or as many as the timeout allows while it hasn't.
    public var hopCount: Int {
        guard let launchEnd else { return Self.maximumHops }
        return min(max(1, Self.hops(in: launchEnd.timeIntervalSince(start))), Self.maximumHops)
    }

    /// When the icon lands for the last time.
    public var end: Date {
        start.addingTimeInterval(Double(hopCount) * Self.hopDuration)
    }

    public func isOver(at date: Date) -> Bool {
        date >= end
    }

    /// 0 on the ground, 1 at the top of a hop. Each hop is a parabola in time, like a
    /// thrown object: fastest leaving and meeting the ground, hanging at the top.
    public func lift(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(start)
        guard elapsed > 0, date < end else { return 0 }
        let phase = elapsed.truncatingRemainder(dividingBy: Self.hopDuration) / Self.hopDuration
        return 4 * phase * (1 - phase)
    }

    /// How far above its resting place the icon is drawn at `date`.
    public func offset(at date: Date, iconHeight: Double) -> Double {
        lift(at: date) * Self.peakOffset(iconHeight: iconHeight)
    }

    /// The icon's opacity at `date` with Reduce Motion on.
    public func reducedMotionOpacity(at date: Date) -> Double {
        1 - Self.reducedMotionFade * lift(at: date)
    }

    /// Whole hops needed to cover `interval`, counting one that has only just begun.
    /// A launch that ends a hair after a landing (within float error of it) doesn't
    /// start another hop.
    private static func hops(in interval: TimeInterval) -> Int {
        Int((interval / hopDuration - 1e-9).rounded(.up))
    }
}

/// The icons bouncing in the dock, one per app being launched. An app's icon is found by
/// bundle identifier or bundle path, the way running apps are matched to dock items, so it
/// keeps bouncing wherever the app shows up: pinned, in the running apps, or both.
public struct LaunchBounces: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var app: AppItem
        public var bounce: LaunchBounce
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public func bounce(for app: AppItem) -> LaunchBounce? {
        entries.first { $0.app.isSameApp(as: app) }?.bounce
    }

    /// Start bouncing `app`'s icon. Returns false if it already is: clicking a bouncing
    /// icon again doesn't restart it.
    @discardableResult
    public mutating func start(_ app: AppItem, at date: Date) -> Bool {
        guard bounce(for: app) == nil else { return false }
        entries.append(Entry(app: app, bounce: LaunchBounce(start: date)))
        return true
    }

    /// `app` finished launching (or failed to, or quit): its icon lands after this hop.
    public mutating func launchEnded(_ app: AppItem, at date: Date) {
        for index in entries.indices where entries[index].app.isSameApp(as: app) {
            entries[index].bounce.launchEnded(at: date)
        }
    }

    /// When the next icon lands for good, if any is bouncing.
    public var nextEnd: Date? {
        entries.map(\.bounce.end).min()
    }

    /// Removes the bounces that are over at `date` and returns their apps.
    public mutating func removeFinished(at date: Date) -> [AppItem] {
        let finished = entries.filter { $0.bounce.isOver(at: date) }.map(\.app)
        entries.removeAll { $0.bounce.isOver(at: date) }
        return finished
    }
}

public extension AppItem {
    /// Whether `other` is the same app: the same bundle identifier, or the same bundle.
    func isSameApp(as other: AppItem) -> Bool {
        if let bundleIdentifier, bundleIdentifier == other.bundleIdentifier { return true }
        return url.normalizedPath == other.url.normalizedPath
    }
}
