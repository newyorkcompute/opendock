import CoreGraphics
import Foundation

/// The geometry behind Dock-style magnification. Pure math, no UI, so it can be unit tested.
///
/// Every item occupies a *slot*: its resting width plus its share of the gap to its
/// neighbors. A slot grows by a raised-cosine function of the distance between the
/// pointer and the slot's resting center, so the effect fades smoothly to nothing at
/// `radius` with no visible edge. Each slot gets its own share of the peak growth: all of
/// it for icons, some for widgets, none for dividers. Magnified slots are laid end to end
/// and the row is then shifted so that the point under the pointer stays under the
/// pointer: the item you're aiming at never slides away, and its neighbors push outward
/// on both sides.
///
/// Positions are in *resting coordinates*: 0 is the leading edge of the first slot when
/// nothing is magnified.
public enum DockMagnification {
    public struct Slot: Hashable, Sendable {
        /// Resting width, including the slot's share of the spacing.
        public var width: Double
        /// Share of the peak growth this slot gets, 0 ... 1: 1 for icons, `widgetGrowth`
        /// for widgets, 0 for items that keep their size (dividers).
        public var growth: Double

        public init(width: Double, growth: Double) {
            self.width = width
            self.growth = max(0, min(growth, 1))
        }
    }

    /// Share of the icons' growth that widget tiles get: 1.15× at the default 1.5×
    /// magnification, from 1.06× at 1.2× to 1.3× at 2×. Tiles are two to three icons wide,
    /// so at this share even a wide one pushes its neighbors about as far as one magnified
    /// icon does, and its text grows by a couple of points instead of a size step.
    public static let widgetGrowth = 0.3

    /// Share of the peak growth an item's slot gets.
    public static func growth(for item: DockItem) -> Double {
        switch item.kind {
        case .app, .folder, .spacer: 1
        case .widget: widgetGrowth
        case .divider: 0
        }
    }

    public struct Row: Hashable, Sendable {
        /// Scale of each slot; 1 for slots that don't grow or are out of range.
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
    ///   - peakScale: Scale of an icon centered exactly under the pointer. A slot with a
    ///     smaller `growth` peaks at `1 + growth * (peakScale - 1)`.
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
            guard slots[i].growth > 0 else { return 1 }
            let center = restingOrigins[i] + slots[i].width / 2
            return 1 + strength * slots[i].growth * falloff(distance: pointer - center, radius: radius)
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

    /// Size of an item drawn at `scale`. Icons grow by the same amount in both directions,
    /// so they stay square and the running indicator under them keeps its size and place.
    /// Items wider than an icon (widgets) grow in height like an icon at the same scale,
    /// and in width in proportion, like their slot.
    public static func itemSize(_ resting: CGSize, scale: Double, iconSize: Double) -> CGSize {
        let heightGrowth = min(resting.width, iconSize) * (scale - 1)
        return CGSize(width: resting.width * scale, height: resting.height + heightGrowth)
    }

    /// The scale to draw a widget tile at, from the height the dock lays it out at: tiles
    /// are as tall as an icon, and `itemSize` grows them like one. Snaps to 1 near rest.
    public static func tileScale(height: Double, iconSize: Double) -> Double {
        guard iconSize > 0, height > 0 else { return 1 }
        let scale = max(1, height / iconSize)
        return scale - 1 < 0.001 ? 1 : scale
    }

    /// The resting size of content that is laid out again at each magnified size (widget
    /// tiles), so its slot keeps its resting width while it's magnified and the dock never
    /// resizes. The content's natural size is its resting size only while it's drawn at
    /// rest. While it's magnified the last resting size is kept, unless the content itself
    /// changes (a clock ticking over), which shows as a new size at an unchanged scale.
    public struct RestingSizeTracker: Equatable, Sendable {
        public private(set) var size: CGSize?
        private var lastNatural = CGSize.zero
        private var lastScale = 1.0

        public init() {}

        /// Record the content's natural size, drawn at `scale`, and return its resting size.
        public mutating func update(natural: CGSize, scale: Double) -> CGSize {
            let scale = scale > 0 ? scale : 1
            let resting: CGSize
            if let size, scale != 1, scale != lastScale || natural == lastNatural {
                resting = size
            } else {
                resting = CGSize(width: natural.width / scale, height: natural.height / scale)
            }
            size = resting
            lastNatural = natural
            lastScale = scale
            return resting
        }
    }
}
