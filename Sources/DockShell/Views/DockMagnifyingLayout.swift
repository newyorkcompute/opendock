import DockCore
import SwiftUI

/// Sizes and spacing of the dock row, derived from settings.
nonisolated struct DockRowMetrics: Equatable {
    var iconSize: CGFloat
    var peakScale: CGFloat

    var spacing: CGFloat { max(6, iconSize * 0.14) }
    var horizontalPadding: CGFloat { 10 }
    var verticalPadding: CGFloat { 8 }
    /// Distance from the bottom of the surface to the bottom of the window (the screen edge).
    var bottomInset: CGFloat { 10 }
    /// Room around the surface for its shadow.
    var shadowMargin: CGFloat { 24 }
    /// Pointer distance at which magnification fades to nothing, as in Apple's Dock.
    var radius: CGFloat { DockMagnification.dockRadiusInSlots * (iconSize + spacing) }
    /// Width of the gap that previews where files dragged in from Finder will land.
    var dropGapWidth: CGFloat { iconSize + spacing }
    var cornerRadius: CGFloat { max(16, iconSize * 0.42) }

    static let labelHeight: CGFloat = 24
    static let labelGap: CGFloat = 8

    init(settings: DockSettings) {
        iconSize = settings.iconSize
        peakScale = settings.peakMagnification
    }
}

/// What a subview of `DockMagnifyingLayout` is.
nonisolated enum DockLayoutRole: Equatable {
    /// Invisible area that keeps the dock under the pointer while it's magnified.
    case hitZone
    /// The material background.
    case surface
    /// The name shown above the hovered item.
    case label
    /// An item in the row, with its share of the peak growth (see
    /// `DockMagnification.Slot.growth`). `hoverable` items get a label; spacers and
    /// dividers don't.
    case item(DockItem.ID?, growth: Double, hoverable: Bool)
}

private nonisolated struct DockLayoutRoleKey: LayoutValueKey {
    static let defaultValue = DockLayoutRole.item(nil, growth: 0, hoverable: false)
}

extension View {
    func dockLayoutRole(_ role: DockLayoutRole) -> some View {
        layoutValue(key: DockLayoutRoleKey.self, value: role)
    }
}

/// A gap in the row that previews where a drag would land (see `DockReorder`).
nonisolated struct DockDropGap: Equatable {
    /// Insertion index among the row's items, not counting the dragged one. Fractional while
    /// the gap moves between two indices.
    var position: CGFloat = 0
    /// 0 ... 1, how far the gap is open.
    var open: CGFloat = 0
    /// Resting width when fully open, spacing included.
    var width: CGFloat = 0
    var growth: Double = 1
}

/// Where things landed in the last layout pass, in the layout's local coordinates.
/// Written during layout and read by pointer tracking. Deliberately not observable:
/// reading it must never cause a re-render.
final class DockGeometry {
    nonisolated struct Slot {
        var id: DockItem.ID?
        var width: CGFloat
        var growth: Double
    }

    var hitZone: CGRect = .zero
    var hoverTargets: [(id: DockItem.ID, frame: CGRect)] = []
    /// Every item with an ID (spacers included) except the one being dragged.
    var itemFrames: [(id: DockItem.ID, frame: CGRect)] = []
    /// Every item in the row at rest, in order, with no gap and nothing left out.
    var restingSlots: [Slot] = []
    /// The row is centered here.
    var rowCenterX: CGFloat = 0
    var halfGap: CGFloat = 0
    /// Origin of the layout in the hosting view (top-left origin).
    var containerOrigin: CGPoint = .zero

    func item(atX x: CGFloat) -> DockItem.ID? {
        hoverTargets.first { x >= $0.frame.minX - halfGap && x < $0.frame.maxX + halfGap }?.id
    }

    /// The item (spacers included) under `x`, if any.
    func anyItem(atX x: CGFloat) -> DockItem.ID? {
        itemFrames.first { x >= $0.frame.minX - halfGap && x < $0.frame.maxX + halfGap }?.id
    }
}

/// Lays the dock out like Apple's Dock with magnification on: items grow upward from a
/// shared baseline around the pointer, neighbors push outward, and the surface widens to
/// fit. Widget tiles take part with a smaller share of the growth. The container's own
/// size never changes with the pointer, so the window doesn't have to be resized while
/// the user sweeps across it.
///
/// While something is dragged over the dock, a gap opens where it would land, and the
/// item being reordered leaves the row (the gap takes its place). The gap is laid out
/// as one more slot, so it magnifies and pushes neighbors aside like the item it stands
/// in for (or like an icon, for files).
///
/// `amount` and the gap's position and opening are animatable, so magnifying in and out
/// and the gap moving are each a single animation on one number.
nonisolated struct DockMagnifyingLayout: Layout {
    var metrics: DockRowMetrics
    /// Pointer x in the layout's local coordinates.
    var pointerX: CGFloat?
    var amount: CGFloat
    var hoveredID: DockItem.ID?
    /// Item being reordered: out of the row while the gap stands in for it.
    var draggedID: DockItem.ID?
    var gap: DockDropGap
    let geometry: DockGeometry

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(amount, AnimatablePair(gap.position, gap.open)) }
        set {
            amount = newValue.first
            gap.position = newValue.second.first
            gap.open = newValue.second.second
        }
    }

    private struct Row {
        /// Subview index of each slot; nil for the gap.
        var itemIndices: [Int?] = []
        var sizes: [CGSize] = []
        var slots: [DockMagnification.Slot] = []
        var hoverIDs: [DockItem.ID?] = []
        var ids: [DockItem.ID?] = []
        var height: CGFloat = 0
        var restingWidth: CGFloat = 0
        /// The dragged item's subview and size, when it's out of the row.
        var dragged: (index: Int, size: CGSize)?
        var resting: [DockGeometry.Slot] = []

        mutating func append(_ index: Int?, id: DockItem.ID?, size: CGSize, slot: DockMagnification.Slot, hoverable: Bool) {
            itemIndices.append(index)
            sizes.append(size)
            slots.append(slot)
            hoverIDs.append(hoverable ? id : nil)
            ids.append(id)
            restingWidth += slot.width
        }
    }

    /// The row's slots. With `withGap`, the dragged item is left out and the gap put in.
    private func measure(_ subviews: Subviews, withGap: Bool) -> Row {
        var row = Row()
        let pieces = withGap ? DockReorder.gapPieces(position: gap.position, width: gap.width * gap.open) : []
        var position = 0
        func appendGap(at index: Int) {
            for piece in pieces where piece.index == index {
                let size = CGSize(width: max(0, piece.width - metrics.spacing), height: metrics.iconSize)
                row.append(nil, id: nil, size: size, slot: .init(width: piece.width, growth: gap.growth), hoverable: false)
            }
        }
        for index in subviews.indices {
            guard case let .item(id, growth, hoverable) = subviews[index][DockLayoutRoleKey.self] else { continue }
            let size = subviews[index].sizeThatFits(.unspecified)
            let slot = DockMagnification.Slot(width: size.width + metrics.spacing, growth: growth)
            row.resting.append(.init(id: id, width: slot.width, growth: growth))
            row.height = max(row.height, size.height)
            if withGap, let id, id == draggedID {
                row.dragged = (index, size)
                continue
            }
            appendGap(at: position)
            row.append(index, id: id, size: size, slot: slot, hoverable: hoverable)
            position += 1
        }
        appendGap(at: position)
        return row
    }

    /// The container's size only depends on the resting slots, but layout runs on every
    /// pointer move; remember the (comparatively costly) overhang for the last slots seen.
    struct Cache {
        var slots: [DockMagnification.Slot] = []
        var peakScale: CGFloat = 0
        var radius: CGFloat = 0
        var overhang: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    /// Sized for the row at rest. A reordered item's gap is as wide as the item, and room
    /// for a Finder drop's gap is set aside up front, so the window keeps its size during a
    /// drag.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let row = measure(subviews, withGap: false)
        if cache.slots != row.slots || cache.peakScale != metrics.peakScale || cache.radius != metrics.radius {
            let overhang = DockMagnification.maximumOverhang(row.slots, peakScale: metrics.peakScale, radius: metrics.radius)
            cache = Cache(slots: row.slots, peakScale: metrics.peakScale, radius: metrics.radius, overhang: max(overhang.leading, overhang.trailing))
        }
        let side = cache.overhang + metrics.horizontalPadding + metrics.shadowMargin
        // No item grows taller than an icon at the peak (see `DockMagnification.itemSize`).
        let growth = metrics.iconSize * (metrics.peakScale - 1)
        let above = max(metrics.verticalPadding + metrics.shadowMargin / 2, growth + Self.labelSpace)
        let height = metrics.bottomInset + metrics.verticalPadding + row.height + above
        return CGSize(width: ceil(row.restingWidth + metrics.dropGapWidth + 2 * side), height: ceil(height))
    }

    private static var labelSpace: CGFloat { DockRowMetrics.labelGap + DockRowMetrics.labelHeight + 4 }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let row = measure(subviews, withGap: true)
        let rowLeft = bounds.midX - row.restingWidth / 2
        let rowBottom = bounds.maxY - metrics.bottomInset - metrics.verticalPadding

        let magnified = DockMagnification.row(
            row.slots,
            pointer: pointerX.map { bounds.minX + $0 - rowLeft },
            peakScale: metrics.peakScale,
            radius: metrics.radius,
            amount: amount
        )

        var frames: [CGRect] = []
        frames.reserveCapacity(row.itemIndices.count)
        for (k, index) in row.itemIndices.enumerated() {
            let size = DockMagnification.itemSize(row.sizes[k], scale: magnified.scales[k], iconSize: metrics.iconSize)
            let midX = rowLeft + magnified.origins[k] + magnified.widths[k] / 2
            frames.append(CGRect(x: midX - size.width / 2, y: rowBottom - size.height, width: size.width, height: size.height))
            if let index {
                subviews[index].place(at: CGPoint(x: midX, y: rowBottom), anchor: .bottom, proposal: ProposedViewSize(size))
            }
        }

        // The dragged item is hidden. Keep it in the gap so that when the drag ends, it's
        // already where it lands.
        if let dragged = row.dragged {
            let gapSlot = row.itemIndices.indices
                .filter { row.itemIndices[$0] == nil }
                .max { magnified.widths[$0] < magnified.widths[$1] }
            let scale = gapSlot.map { magnified.scales[$0] } ?? 1
            let midX = gapSlot.map { frames[$0].midX } ?? bounds.midX
            let size = DockMagnification.itemSize(dragged.size, scale: scale, iconSize: metrics.iconSize)
            subviews[dragged.index].place(at: CGPoint(x: midX, y: rowBottom), anchor: .bottom, proposal: ProposedViewSize(size))
        }

        // Edges of what's drawn in each slot, with the slot's share of the spacing taken off.
        // For icons that's their frame; for a piece of the gap it can be negative, so the
        // surface doesn't jump as the piece grows from nothing.
        var leading = CGFloat.infinity
        var trailing = -CGFloat.infinity
        for k in row.slots.indices {
            let center = rowLeft + magnified.origins[k] + magnified.widths[k] / 2
            let half = (magnified.widths[k] - metrics.spacing * magnified.scales[k]) / 2
            leading = min(leading, center - half)
            trailing = max(trailing, center + half)
        }
        if row.slots.isEmpty { (leading, trailing) = (bounds.midX, bounds.midX) }
        let surface = CGRect(
            x: leading - metrics.horizontalPadding,
            y: rowBottom - row.height - metrics.verticalPadding,
            width: (trailing - leading) + 2 * metrics.horizontalPadding,
            height: row.height + 2 * metrics.verticalPadding
        )
        let zoneTop = min(surface.minY, frames.map(\.minY).min() ?? surface.minY)
        let zone = CGRect(x: surface.minX, y: zoneTop, width: surface.width, height: bounds.maxY - zoneTop)

        let hoveredFrame = hoveredID.flatMap { id in row.hoverIDs.firstIndex(of: id).map { frames[$0] } }

        for index in subviews.indices {
            switch subviews[index][DockLayoutRoleKey.self] {
            case .surface:
                subviews[index].place(at: surface.origin, proposal: ProposedViewSize(surface.size))
            case .hitZone:
                subviews[index].place(at: zone.origin, proposal: ProposedViewSize(zone.size))
            case .label:
                let size = subviews[index].sizeThatFits(.unspecified)
                let anchor = hoveredFrame ?? CGRect(x: bounds.midX, y: zoneTop, width: 0, height: 0)
                let halfWidth = size.width / 2
                let midX = min(max(anchor.midX, bounds.minX + halfWidth), bounds.maxX - halfWidth)
                let bottom = max(anchor.minY - DockRowMetrics.labelGap, bounds.minY + size.height)
                subviews[index].place(at: CGPoint(x: midX, y: bottom), anchor: .bottom, proposal: ProposedViewSize(size))
            case .item:
                break
            }
        }

        let local = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let targets = zip(row.hoverIDs, frames).compactMap { id, frame in
            id.map { (id: $0, frame: frame.applying(local)) }
        }
        let allFrames = zip(row.ids, frames).compactMap { id, frame in
            id.map { (id: $0, frame: frame.applying(local)) }
        }
        let halfGap = metrics.spacing / 2
        let resting = row.resting
        let rowCenterX = bounds.midX - bounds.minX
        // SwiftUI lays out on the main thread.
        MainActor.assumeIsolated {
            geometry.hitZone = zone.applying(local)
            geometry.halfGap = halfGap
            geometry.hoverTargets = targets
            geometry.itemFrames = allFrames
            geometry.restingSlots = resting
            geometry.rowCenterX = rowCenterX
        }
    }
}

extension Animation {
    /// Apple's Dock grows and settles back along an ease-in-out curve of about 130 ms in
    /// both directions, with no overshoot (sampled from its accessibility frames).
    static let dockMagnify = Animation.easeInOut(duration: 0.13)
    static let dockDemagnify = Animation.easeInOut(duration: 0.13)
    /// The gap a drag opens moves along the same curve, so icons making room for it move
    /// like they do when they magnify.
    static let dockDropGap = Animation.easeInOut(duration: 0.13)
}
