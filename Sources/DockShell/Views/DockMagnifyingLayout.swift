import DockCore
import SwiftUI
import SystemServices

/// An item in the dock row: one of the pinned items, a running app shown after them, a
/// recently used app shown after those, or the Trash at the very end.
nonisolated enum DockRowItemID: Hashable, Sendable {
    case pinned(DockItem.ID)
    case running(RunningDockApp.ID)
    case recent(RecentDockApp.ID)
    case trash

    var pinnedID: DockItem.ID? {
        if case let .pinned(id) = self { return id }
        return nil
    }

    /// What dragging this item does (see `DockRowDrag`); nil for the Trash, which can't be
    /// dragged.
    var dragItem: DockRowDrag.Item? {
        switch self {
        case .pinned: .pinned
        case .running: .running
        case .recent: .recent
        case .trash: nil
        }
    }
}

/// Sizes and spacing of the dock row, derived from settings.
///
/// The row runs along the screen edge the dock is on, so its measurements are given
/// *along* the edge and in *depth* away from it (see `DockEdgeSpace`), the same on every
/// edge.
nonisolated struct DockRowMetrics: Equatable {
    var edge: DockSettings.Edge
    var iconSize: CGFloat
    var peakScale: CGFloat
    /// How far past its magnified size an icon can hop (while its app launches, or when
    /// something lands in a folder): the top of a hop of an icon at the peak scale.
    var launchBounceHeight: CGFloat

    var axis: DockAxis { edge.axis }
    var spacing: CGFloat { max(6, iconSize * 0.14) }
    /// Padding between the surface's ends and the first and last item.
    var endPadding: CGFloat { 10 }
    /// Padding between the surface's sides and the items.
    var sidePadding: CGFloat { 8 }
    /// Distance from the surface to the screen edge (the window reaches the edge).
    var edgeInset: CGFloat { 10 }
    /// Room around the surface for its shadow.
    var shadowMargin: CGFloat { 24 }
    /// Pointer distance at which magnification fades to nothing, as in Apple's Dock.
    var radius: CGFloat { DockMagnification.dockRadiusInSlots * (iconSize + spacing) }
    /// Length of the gap that previews where files dragged in from Finder will land.
    var dropGapWidth: CGFloat { iconSize + spacing }
    var cornerRadius: CGFloat { max(16, iconSize * 0.42) }

    static let labelHeight: CGFloat = 24
    /// The widest a label gets beside a side-edge dock; longer names are truncated. The
    /// window sets this much aside, as it does `labelHeight` above a bottom dock.
    static let labelMaxWidth: CGFloat = 240
    static let labelGap: CGFloat = 8

    /// Room past the magnified icons for the label: its height above a bottom dock, its
    /// width beside a side dock.
    var labelSpace: CGFloat {
        Self.labelGap + (edge.isVertical ? Self.labelMaxWidth : Self.labelHeight) + 4
    }

    init(settings: DockSettings) {
        edge = settings.edge
        iconSize = settings.iconSize
        peakScale = settings.peakMagnification
        // Folders hop whatever the launch animation setting says, so the room is always kept.
        launchBounceHeight = LaunchBounce.peakOffset(iconHeight: settings.iconSize * settings.peakMagnification)
    }
}

/// What a subview of `DockMagnifyingLayout` is.
nonisolated enum DockLayoutRole: Equatable {
    /// Invisible area that keeps the dock under the pointer while it's magnified.
    case hitZone
    /// The material background.
    case surface
    /// The name shown beside the hovered item, away from the screen edge.
    case label
    /// An item in the row, with its share of the peak growth (see
    /// `DockMagnification.Slot.growth`). `hoverable` items get a label; spacers and
    /// dividers don't.
    case item(DockRowItemID?, growth: Double, hoverable: Bool)
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
    /// Resting length along the row when fully open, spacing included.
    var width: CGFloat = 0
    var growth: Double = 1
}

/// Where things landed in the last layout pass, in the layout's local coordinates.
/// Written during layout and read by pointer tracking. Deliberately not observable:
/// reading it must never cause a re-render.
final class DockGeometry {
    nonisolated struct Slot {
        var id: DockRowItemID?
        /// Resting length along the row, spacing included.
        var width: CGFloat
        var growth: Double
    }

    /// The edge the layout was for, which says which way the row runs.
    var edge: DockSettings.Edge = .bottom
    var hitZone: CGRect = .zero
    var hoverTargets: [(id: DockRowItemID, frame: CGRect)] = []
    /// Every item with an ID (spacers included) except the one being dragged and the hidden ones.
    var itemFrames: [(id: DockRowItemID, frame: CGRect)] = []
    /// Items that have no length along the row (a widget tile with nothing to show). They
    /// keep their place in the row and in `restingSlots`, with a zero-width slot, but can't
    /// be seen, hovered, or selected.
    var hiddenItemIDs: Set<DockRowItemID> = []
    /// Every item in the row at rest, in order, with no gap and nothing left out.
    var restingSlots: [Slot] = []
    /// The row is centered here, along the edge.
    var rowCenter: CGFloat = 0
    var halfGap: CGFloat = 0
    /// Origin of the layout in the hosting view (top-left origin).
    var containerOrigin: CGPoint = .zero

    /// `point`'s position along the row.
    func along(_ point: CGPoint) -> CGFloat {
        edge.axis.along(point)
    }

    /// The hoverable item whose slot `point` is in along the row, wherever it is across it.
    func item(at point: CGPoint) -> DockRowItemID? {
        hoverTargets.first { spans($0.frame, point) }?.id
    }

    /// The item (spacers included) whose slot `point` is in along the row, if any.
    func anyItem(at point: CGPoint) -> DockRowItemID? {
        itemFrames.first { spans($0.frame, point) }?.id
    }

    private func spans(_ frame: CGRect, _ point: CGPoint) -> Bool {
        let span = edge.axis.span(of: frame)
        let position = along(point)
        return position >= span.lowerBound - halfGap && position < span.upperBound + halfGap
    }
}

/// Lays the dock out like Apple's Dock with magnification on: items grow away from the
/// screen edge from a shared baseline around the pointer, neighbors push outward along the
/// edge, and the surface lengthens to fit. Widget tiles take part with a smaller share of
/// the growth. The container's own size never changes with the pointer, so the window
/// doesn't have to be resized while the user sweeps across it.
///
/// The row runs along whichever edge the dock is on. The layout works in `DockEdgeSpace`
/// coordinates (positions along the edge and depths away from it) and converts to the
/// container's at the end, so the bottom and the sides share every line of it.
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
    /// Pointer position along the row, in the layout's local coordinates.
    var pointer: CGFloat?
    /// The keyboard's selection while the pointer is off the dock: the row magnifies around
    /// its resting center, as if the pointer were there, instead of around `pointer`.
    var selectedID: DockRowItemID?
    var amount: CGFloat
    var hoveredID: DockRowItemID?
    /// Item being dragged: out of the row while the gap stands in for it.
    var draggedID: DockRowItemID?
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
        var hoverIDs: [DockRowItemID?] = []
        var ids: [DockRowItemID?] = []
        /// The thickest item across the row.
        var thickness: CGFloat = 0
        var restingLength: CGFloat = 0
        /// The dragged item's subview and size, when it's out of the row.
        var dragged: (index: Int, size: CGSize)?
        var resting: [DockGeometry.Slot] = []
        /// Items in the row that have no length and so can't be seen, hovered, or selected.
        var hiddenIDs: Set<DockRowItemID> = []

        mutating func append(
            _ index: Int?, id: DockRowItemID?, size: CGSize, slot: DockMagnification.Slot, hoverable: Bool
        ) {
            itemIndices.append(index)
            sizes.append(size)
            slots.append(slot)
            hoverIDs.append(hoverable ? id : nil)
            ids.append(id)
            restingLength += slot.width
        }
    }

    /// The row's slots. With `withGap`, the dragged item is left out and the gap put in.
    private func measure(_ subviews: Subviews, withGap: Bool) -> Row {
        let axis = metrics.axis
        var row = Row()
        let pieces = withGap ? DockReorder.gapPieces(position: gap.position, width: gap.width * gap.open) : []
        var position = 0
        func appendGap(at index: Int) {
            for piece in pieces where piece.index == index {
                let size = axis.size(length: max(0, piece.width - metrics.spacing), thickness: metrics.iconSize)
                row.append(
                    nil, id: nil, size: size, slot: .init(width: piece.width, growth: gap.growth), hoverable: false)
            }
        }
        for index in subviews.indices {
            guard case let .item(id, growth, hoverable) = subviews[index][DockLayoutRoleKey.self] else { continue }
            let size = subviews[index].sizeThatFits(.unspecified)
            let length = axis.length(of: size)
            // An item with no length along the row (a widget tile with nothing to show)
            // keeps its place in the row but takes no slot, so the row closes up over it:
            // no spacing, no magnification, no label.
            let hidden = length <= 0
            let slot = DockMagnification.Slot(
                width: hidden ? 0 : length + metrics.spacing, growth: hidden ? 0 : growth)
            row.resting.append(.init(id: id, width: slot.width, growth: slot.growth))
            if !hidden { row.thickness = max(row.thickness, axis.thickness(of: size)) }
            if withGap, let draggedID, id == draggedID {
                row.dragged = (index, size)
                continue
            }
            appendGap(at: position)
            row.append(index, id: id, size: size, slot: slot, hoverable: hoverable && !hidden)
            if hidden, let id { row.hiddenIDs.insert(id) }
            position += 1
        }
        appendGap(at: position)
        // A row of nothing but hidden items still has the dock's depth.
        if row.thickness == 0 { row.thickness = metrics.iconSize }
        return row
    }

    /// What the row magnifies around, in resting coordinates (from the row's start): the
    /// keyboard's selection while it has one in the row, else the pointer.
    private func magnificationPointer(space: DockEdgeSpace, rowStart: CGFloat, row: Row) -> Double? {
        if let selectedID {
            var position: CGFloat = 0
            for (k, slot) in row.slots.enumerated() {
                if row.ids[k] == selectedID { return Double(position + slot.width / 2) }
                position += slot.width
            }
        }
        guard let pointer else { return nil }
        return Double(space.span.lowerBound + pointer - rowStart)
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

    /// Sized for the row at rest. A reordered item's gap is as long as the item, and room
    /// for a Finder drop's gap is set aside up front, so the window keeps its size during a
    /// drag.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let row = measure(subviews, withGap: false)
        if cache.slots != row.slots || cache.peakScale != metrics.peakScale || cache.radius != metrics.radius {
            let overhang = DockMagnification.maximumOverhang(
                row.slots, peakScale: metrics.peakScale, radius: metrics.radius)
            cache = Cache(
                slots: row.slots, peakScale: metrics.peakScale, radius: metrics.radius,
                overhang: max(overhang.leading, overhang.trailing))
        }
        let end = cache.overhang + metrics.endPadding + metrics.shadowMargin
        // No item grows thicker than an icon at the peak (see `DockMagnification.itemSize`).
        // Past that, room for the label, or for the top of a launch bounce if that's further.
        let growth = metrics.iconSize * (metrics.peakScale - 1)
        let headroom = max(metrics.labelSpace, metrics.launchBounceHeight)
        let beyond = max(metrics.sidePadding + metrics.shadowMargin / 2, growth + headroom)
        let depth = metrics.edgeInset + metrics.sidePadding + row.thickness + beyond
        return metrics.axis.size(
            length: ceil(row.restingLength + metrics.dropGapWidth + 2 * end),
            thickness: ceil(depth)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let axis = metrics.axis
        let space = DockEdgeSpace(edge: metrics.edge, bounds: bounds)
        let row = measure(subviews, withGap: true)
        let rowStart = space.middle - row.restingLength / 2
        // The items' near sides all sit here; magnified, they grow away from the edge.
        let baseline = metrics.edgeInset + metrics.sidePadding

        let magnified = DockMagnification.row(
            row.slots,
            pointer: magnificationPointer(space: space, rowStart: rowStart, row: row),
            peakScale: metrics.peakScale,
            radius: metrics.radius,
            amount: amount
        )

        func slotFrame(for size: CGSize, inSlot k: Int) -> CGRect {
            let middle = rowStart + magnified.origins[k] + magnified.widths[k] / 2
            return space.rect(
                along: middle - axis.length(of: size) / 2, length: axis.length(of: size),
                depth: baseline, thickness: axis.thickness(of: size))
        }

        var frames: [CGRect] = []
        frames.reserveCapacity(row.itemIndices.count)
        for (k, index) in row.itemIndices.enumerated() {
            let size = DockMagnification.itemSize(
                row.sizes[k], scale: magnified.scales[k], iconSize: metrics.iconSize, axis: axis)
            let frame = slotFrame(for: size, inSlot: k)
            frames.append(frame)
            if let index {
                place(subviews[index], in: frame, space: space)
            }
        }

        // The dragged item is hidden. Keep it in the gap so that when the drag ends, it's
        // already where it lands.
        if let dragged = row.dragged {
            let gapSlot = row.itemIndices.indices
                .filter { row.itemIndices[$0] == nil }
                .max { magnified.widths[$0] < magnified.widths[$1] }
            let scale = gapSlot.map { magnified.scales[$0] } ?? 1
            let size = DockMagnification.itemSize(dragged.size, scale: scale, iconSize: metrics.iconSize, axis: axis)
            let frame =
                gapSlot.map { slotFrame(for: size, inSlot: $0) }
                ?? space.rect(
                    along: space.middle - axis.length(of: size) / 2, length: axis.length(of: size),
                    depth: baseline, thickness: axis.thickness(of: size))
            place(subviews[dragged.index], in: frame, space: space)
        }

        // Ends of what's drawn in each slot, with the slot's share of the spacing taken off.
        // For icons that's their frame; for a piece of the gap it can be negative, so the
        // surface doesn't jump as the piece grows from nothing.
        var leading = CGFloat.infinity
        var trailing = -CGFloat.infinity
        for k in row.slots.indices {
            let center = rowStart + magnified.origins[k] + magnified.widths[k] / 2
            let half = (magnified.widths[k] - metrics.spacing * magnified.scales[k]) / 2
            leading = min(leading, center - half)
            trailing = max(trailing, center + half)
        }
        if row.slots.isEmpty { (leading, trailing) = (space.middle, space.middle) }
        let surface = space.rect(
            along: leading - metrics.endPadding,
            length: (trailing - leading) + 2 * metrics.endPadding,
            depth: metrics.edgeInset,
            thickness: row.thickness + 2 * metrics.sidePadding
        )
        // From the screen edge to the far side of the surface or of the furthest-reaching
        // magnified item.
        let zoneDepth = max(space.farDepth(of: surface), frames.map { space.farDepth(of: $0) }.max() ?? 0)
        let zone = space.rect(
            along: axis.span(of: surface).lowerBound, length: axis.length(of: surface.size),
            depth: 0, thickness: zoneDepth)

        let hoveredFrame = hoveredID.flatMap { id in row.hoverIDs.firstIndex(of: id).map { frames[$0] } }

        for index in subviews.indices {
            switch subviews[index][DockLayoutRoleKey.self] {
            case .surface:
                subviews[index].place(at: surface.origin, proposal: ProposedViewSize(surface.size))
            case .hitZone:
                subviews[index].place(at: zone.origin, proposal: ProposedViewSize(zone.size))
            case .label:
                // Centered on the hovered item (or on the dock, for a profile's name), just
                // past it away from the screen edge, and kept inside the window. Beside a
                // side dock it's held to the width the window set aside for it.
                let size = subviews[index].sizeThatFits(
                    metrics.edge.isVertical
                        ? ProposedViewSize(width: DockRowMetrics.labelMaxWidth, height: nil) : .unspecified)
                let anchor =
                    hoveredFrame ?? space.rect(along: space.middle, length: 0, depth: zoneDepth, thickness: 0)
                let length = axis.length(of: size)
                let thickness = axis.thickness(of: size)
                let anchorSpan = axis.span(of: anchor)
                let middle = min(
                    max((anchorSpan.lowerBound + anchorSpan.upperBound) / 2, space.span.lowerBound + length / 2),
                    space.span.upperBound - length / 2)
                let depth = min(space.farDepth(of: anchor) + DockRowMetrics.labelGap, space.depth - thickness)
                let frame = space.rect(along: middle - length / 2, length: length, depth: depth, thickness: thickness)
                subviews[index].place(at: frame.origin, proposal: ProposedViewSize(frame.size))
            case .item:
                break
            }
        }

        let local = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        let targets = zip(row.hoverIDs, frames).compactMap { id, frame in
            id.map { (id: $0, frame: frame.applying(local)) }
        }
        // Hidden items have no frame to hit (with the gaps counted, a zero-length frame
        // would still catch clicks and drags meant for its neighbors).
        let allFrames: [(id: DockRowItemID, frame: CGRect)] = zip(row.ids, frames).compactMap { id, frame in
            guard let id, !row.hiddenIDs.contains(id) else { return nil }
            return (id: id, frame: frame.applying(local))
        }
        let halfGap = metrics.spacing / 2
        let resting = row.resting
        let hidden = row.hiddenIDs
        let rowCenter = space.middle - space.span.lowerBound
        let edge = metrics.edge
        // SwiftUI lays out on the main thread.
        MainActor.assumeIsolated {
            geometry.edge = edge
            geometry.hitZone = zone.applying(local)
            geometry.halfGap = halfGap
            geometry.hoverTargets = targets
            geometry.itemFrames = allFrames
            geometry.hiddenItemIDs = hidden
            geometry.restingSlots = resting
            geometry.rowCenter = rowCenter
        }
    }

    /// Places an item in `frame`, anchored to the middle of its side nearest the screen
    /// edge, so an item that ends up smaller than its frame still sits on the baseline.
    private func place(_ subview: LayoutSubview, in frame: CGRect, space: DockEdgeSpace) {
        subview.place(
            at: space.anchor(of: frame), anchor: metrics.edge.unitPoint, proposal: ProposedViewSize(frame.size))
    }
}

nonisolated extension DockSettings.Edge {
    /// The point of an item that sits on the dock's baseline: the middle of its side
    /// nearest the screen edge.
    var unitPoint: UnitPoint {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// The same, as an alignment.
    var alignment: Alignment {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// The side of a view that faces the screen edge.
    var facingSide: SwiftUI.Edge.Set {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// Where a popover's arrow goes so the popover opens away from the screen edge.
    var popoverArrowEdge: SwiftUI.Edge {
        switch self {
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
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
