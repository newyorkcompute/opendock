import Foundation

/// The puff of smoke that plays where an item dragged off the dock is let go: a cloud of
/// soft gray puffs that billows out from the icon's center and fades away. Our own
/// drawing, not Apple's; pure math here, so the frames can be unit tested and the shell
/// only has to draw circles.
///
/// Puffs are in unit coordinates: the whole cloud fits in the square from -1 to 1, which
/// the shell scales to about twice the icon's size.
public enum PoofCloud {
    /// How long the poof plays.
    public static let duration: TimeInterval = 0.45

    /// One puff of the cloud at one moment.
    public struct Puff: Equatable, Sendable {
        /// Center, in unit coordinates.
        public var x: Double
        public var y: Double
        /// Radius, in unit coordinates.
        public var radius: Double
        /// 0 ... 1.
        public var opacity: Double

        public init(x: Double, y: Double, radius: Double, opacity: Double) {
            self.x = x
            self.y = y
            self.radius = radius
            self.opacity = opacity
        }
    }

    /// The puffs around the center one. Unevenly spaced and sized so the cloud doesn't
    /// look like a gear; fixed rather than random so every poof, and every test, is the same.
    private static let ring: [(angle: Double, spread: Double, size: Double)] = [
        (angle: 0.02, spread: 1.0, size: 1.0),
        (angle: 0.15, spread: 0.9, size: 0.8),
        (angle: 0.30, spread: 1.1, size: 0.9),
        (angle: 0.44, spread: 0.95, size: 1.1),
        (angle: 0.57, spread: 1.05, size: 0.85),
        (angle: 0.72, spread: 0.85, size: 1.0),
        (angle: 0.86, spread: 1.15, size: 0.95),
    ]

    /// Number of puffs in every frame.
    public static var puffCount: Int { ring.count + 1 }

    /// The cloud `progress` (0 ... 1, clamped) of the way through the poof. The puffs
    /// appear in the first instant, drift outward and grow as they thin, and are gone at
    /// the end. With `reduceMotion`, nothing moves: the cloud just fades.
    public static func puffs(at progress: Double, reduceMotion: Bool = false) -> [Puff] {
        let progress = min(max(progress, 0), 1)
        // Fast at first, settling toward the end, like smoke losing its push.
        let eased = 1 - (1 - progress) * (1 - progress)
        let opacity = Self.opacity(at: progress)
        let spread = reduceMotion ? 0.5 : 0.2 + 0.35 * eased
        let puffRadius = reduceMotion ? 0.3 : 0.2 + 0.1 * eased
        let centerRadius = reduceMotion ? 0.5 : 0.35 + 0.2 * eased
        let center = Puff(x: 0, y: 0, radius: centerRadius, opacity: opacity)
        return [center]
            + ring.map { puff in
                let angle = puff.angle * 2 * .pi
                let distance = spread * puff.spread
                return Puff(
                    x: cos(angle) * distance,
                    y: sin(angle) * distance,
                    radius: puffRadius * puff.size,
                    opacity: opacity
                )
            }
    }

    /// Fully there almost at once, then thinning out, faster toward the end.
    static func opacity(at progress: Double) -> Double {
        let rise = 0.1
        guard progress >= rise else { return progress / rise }
        return pow(1 - (progress - rise) / (1 - rise), 1.6)
    }
}
