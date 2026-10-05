import Foundation

/// The geometry behind Dock-style magnification. Pure math, no UI, so it can be unit tested.
///
/// Every item occupies a *slot*: its resting width plus its share of the gap to its
/// neighbors. A slot that magnifies grows by a raised-cosine function of the distance
/// between the pointer and the slot's resting center, so the effect fades smoothly to
/// nothing at `radius` with no visible edge. Magnified slots are laid end to end and the
/// row is then shifted so that the point under the pointer stays under the pointer: the
/// item you're aiming at never slides away, and its neighbors push outward on both sides.
///
/// Positions are in *resting coordinates*: 0 is the leading edge of the first slot when
/// nothing is magnified.
public enum DockMagnification {
    public struct Slot: Hashable, Sendable {
        /// Resting width, including the slot's share of the spacing.
        public var width: Double
        /// False for items that keep their size (widgets, dividers).
        public var magnifies: Bool

        public init(width: Double, magnifies: Bool) {
            self.width = width
            self.magnifies = magnifies
        }
    }

    public struct Row: Hashable, Sendable {
        /// Scale of each slot; 1 for slots that don't magnify or are out of range.
        public var scales: [Double]
        /// Leading edge of each slot after magnification.
        public var origins: [Double]
        /// Width of each slot after magnification.
        public var widths: [Double]

        public var leadingEdge: Double { origins.first ?? 0 }
        public var trailingEdge: Double {
            guard let origin = origins.last, let width = widths.last else { return 0 }
            return origin + width
        }

        /// Index of the slot whose magnified extent contains `x`.
        public func slotIndex(at x: Double) -> Int? {
            origins.indices.first { x >= origins[$0] && x < origins[$0] + widths[$0] }
        }
    }

    /// Radius that matches Apple's Dock, in resting slot widths. Measured through the
    /// Dock's accessibility frames (macOS 26): the curve depends only on resting slots,
    /// not on the magnified size.
    public static let dockRadiusInSlots = 3.2

    /// 1 at distance 0, easing to 0 at `radius` with zero slope at both ends. A raised
    /// cosine to the power 0.6, fitted to Apple's Dock: at 1, 2 and 3 slots of a 3.2-slot
    /// radius it gives 0.86, 0.50 and 0.07 (Dock: 0.87, 0.50, 0.07).
    public static func falloff(distance: Double, radius: Double) -> Double {
        guard radius > 0 else { return 0 }
        let d = abs(distance)
        guard d < radius else { return 0 }
        return pow((1 + cos(Double.pi * d / radius)) / 2, 0.6)
    }

    /// Lay out `slots` magnified around `pointer`.
    ///
    /// - Parameters:
    ///   - pointer: Pointer position in resting coordinates, or nil for no magnification.
    ///   - peakScale: Scale of a slot centered exactly under the pointer.
    ///   - radius: Distance from the pointer at which magnification reaches zero.
    ///   - amount: 0 ... 1. Animating this from 0 to 1 grows the effect in place.
    public static func row(
        _ slots: [Slot],
        pointer: Double?,
        peakScale: Double,
        radius: Double,
        amount: Double = 1
    ) -> Row {
        var restingOrigins: [Double] = []
        restingOrigins.reserveCapacity(slots.count)
        var x = 0.0
        for slot in slots {
            restingOrigins.append(x)
            x += slot.width
        }
        let restingWidth = x

        let strength = max(0, min(amount, 1)) * (peakScale - 1)
        guard let pointer, strength > 0, !slots.isEmpty else {
            return Row(scales: slots.map { _ in 1 }, origins: restingOrigins, widths: slots.map(\.width))
        }

        let scales = slots.indices.map { i -> Double in
            guard slots[i].magnifies else { return 1 }
            let center = restingOrigins[i] + slots[i].width / 2
            return 1 + strength * falloff(distance: pointer - center, radius: radius)
        }
        let widths = slots.indices.map { slots[$0].width * scales[$0] }
        let magnifiedWidth = widths.reduce(0, +)

        // Where the resting point under the pointer lands in the magnified row, measured
        // from the magnified row's leading edge. Inside a slot, it keeps its fraction.
        let pointerInRow: Double
        if pointer <= 0 {
            pointerInRow = pointer
        } else if pointer >= restingWidth {
            pointerInRow = magnifiedWidth + (pointer - restingWidth)
        } else {
            let k = restingOrigins.lastIndex { $0 <= pointer } ?? 0
            let fraction = slots[k].width > 0 ? (pointer - restingOrigins[k]) / slots[k].width : 0
            pointerInRow = widths[..<k].reduce(0, +) + fraction * widths[k]
        }

        let shift = pointer - pointerInRow
        var origins: [Double] = []
        origins.reserveCapacity(slots.count)
        var cursor = shift
        for width in widths {
            origins.append(cursor)
            cursor += width
        }
        return Row(scales: scales, origins: origins, widths: widths)
    }

    /// The furthest the magnified row can extend past its resting edges, over every
    /// pointer position. Size containers with this so nothing ever clips.
    public static func maximumOverhang(
        _ slots: [Slot],
        peakScale: Double,
        radius: Double
    ) -> (leading: Double, trailing: Double) {
        let restingWidth = slots.reduce(0) { $0 + $1.width }
        guard peakScale > 1, !slots.isEmpty, restingWidth > 0 else { return (0, 0) }

        let narrowest = slots.map(\.width).filter { $0 > 0 }.min() ?? restingWidth
        let span = restingWidth + 2 * radius
        let step = max(narrowest / 8, span / 2000, 0.5)
        var leading = 0.0
        var trailing = 0.0
        var pointer = -radius
        while pointer <= restingWidth + radius {
            let row = row(slots, pointer: pointer, peakScale: peakScale, radius: radius)
            leading = max(leading, -row.leadingEdge)
            trailing = max(trailing, row.trailingEdge - restingWidth)
            pointer += step
        }
        return (leading, trailing)
    }
}
