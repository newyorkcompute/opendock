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
    /// Pointer distance at which magnification fades to nothing: three resting items.
    var radius: CGFloat { 3 * (iconSize + spacing) }
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
    /// An item in the row. `hoverable` items get a label; spacers and dividers don't.
    case item(DockItem.ID?, magnifies: Bool, hoverable: Bool)
}

private nonisolated struct DockLayoutRoleKey: LayoutValueKey {
    static let defaultValue = DockLayoutRole.item(nil, magnifies: false, hoverable: false)
}

extension View {
    func dockLayoutRole(_ role: DockLayoutRole) -> some View {
        layoutValue(key: DockLayoutRoleKey.self, value: role)
    }
}

/// Where things landed in the last layout pass, in the layout's local coordinates.
/// Written during layout and read by pointer tracking. Deliberately not observable:
/// reading it must never cause a re-render.
final class DockGeometry {
    var hitZone: CGRect = .zero
    var hoverTargets: [(id: DockItem.ID, frame: CGRect)] = []
    /// Every item with an ID (spacers included), for drop targeting.
    var itemFrames: [(id: DockItem.ID, frame: CGRect)] = []
    var halfGap: CGFloat = 0
    /// Origin of the layout in the hosting view (top-left origin).
    var containerOrigin: CGPoint = .zero

    func item(atX x: CGFloat) -> DockItem.ID? {
        hoverTargets.first { x >= $0.frame.minX - halfGap && x < $0.frame.maxX + halfGap }?.id
    }

    /// The item a drop at `x` lands on: the one under it, else the nearest.
    func dropTarget(atX x: CGFloat) -> DockItem.ID? {
        itemFrames.min { abs($0.frame.midX - x) < abs($1.frame.midX - x) }?.id
    }
}

/// Lays the dock out like Apple's Dock with magnification on: items grow upward from a
/// shared baseline around the pointer, neighbors push outward, and the surface widens to
/// fit. The container's own size never changes with the pointer, so the window doesn't
/// have to be resized while the user sweeps across it.
///
/// `amount` is animatable, so magnifying in and out is a single spring on one number.
nonisolated struct DockMagnifyingLayout: Layout {
    var metrics: DockRowMetrics
    /// Pointer x in the layout's local coordinates.
    var pointerX: CGFloat?
    var amount: CGFloat
    var hoveredID: DockItem.ID?
    let geometry: DockGeometry

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    private struct Row {
        var itemIndices: [Int] = []
        var sizes: [CGSize] = []
        var slots: [DockMagnification.Slot] = []
        var hoverIDs: [DockItem.ID?] = []
        var ids: [DockItem.ID?] = []
        var height: CGFloat = 0
        var restingWidth: CGFloat = 0
    }

    private func measure(_ subviews: Subviews) -> Row {
        var row = Row()
        for index in subviews.indices {
            guard case let .item(id, magnifies, hoverable) = subviews[index][DockLayoutRoleKey.self] else { continue }
            row.ids.append(id)
            let size = subviews[index].sizeThatFits(.unspecified)
            row.itemIndices.append(index)
            row.sizes.append(size)
            row.slots.append(.init(width: size.width + metrics.spacing, magnifies: magnifies))
            row.hoverIDs.append(hoverable ? id : nil)
            row.height = max(row.height, size.height)
            row.restingWidth += size.width + metrics.spacing
        }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let row = measure(subviews)
        if cache.slots != row.slots || cache.peakScale != metrics.peakScale || cache.radius != metrics.radius {
            let overhang = DockMagnification.maximumOverhang(row.slots, peakScale: metrics.peakScale, radius: metrics.radius)
            cache = Cache(slots: row.slots, peakScale: metrics.peakScale, radius: metrics.radius, overhang: max(overhang.leading, overhang.trailing))
        }
        let side = cache.overhang + metrics.horizontalPadding + metrics.shadowMargin
        let growth = metrics.iconSize * (metrics.peakScale - 1)
        let above = max(metrics.verticalPadding + metrics.shadowMargin / 2, growth + Self.labelSpace)
        let height = metrics.bottomInset + metrics.verticalPadding + row.height + above
        return CGSize(width: ceil(row.restingWidth + 2 * side), height: ceil(height))
    }

    private static var labelSpace: CGFloat { DockRowMetrics.labelGap + DockRowMetrics.labelHeight + 4 }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let row = measure(subviews)
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
            let base = row.sizes[k]
            let scale = magnified.scales[k]
            // Grow by the same amount in both directions so square icons stay square and
            // the running indicator under them keeps its size and place.
            let growth = base.width * (scale - 1)
            let size = CGSize(width: base.width + growth, height: base.height + growth)
            let midX = rowLeft + magnified.origins[k] + magnified.widths[k] / 2
            frames.append(CGRect(x: midX - size.width / 2, y: rowBottom - size.height, width: size.width, height: size.height))
            subviews[index].place(at: CGPoint(x: midX, y: rowBottom), anchor: .bottom, proposal: ProposedViewSize(size))
        }

        let surface = CGRect(
            x: (frames.first?.minX ?? bounds.midX) - metrics.horizontalPadding,
            y: rowBottom - row.height - metrics.verticalPadding,
            width: ((frames.last?.maxX ?? bounds.midX) - (frames.first?.minX ?? bounds.midX)) + 2 * metrics.horizontalPadding,
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
        // SwiftUI lays out on the main thread.
        MainActor.assumeIsolated {
            geometry.hitZone = zone.applying(local)
            geometry.halfGap = halfGap
            geometry.hoverTargets = targets
            geometry.itemFrames = allFrames
        }
    }
}

extension Animation {
    /// Growing as the pointer arrives: quick, with a hint of overshoot.
    static let dockMagnify = Animation.spring(response: 0.24, dampingFraction: 0.82)
    /// Settling back when it leaves: a touch slower and fully damped.
    static let dockDemagnify = Animation.spring(response: 0.3, dampingFraction: 0.92)
}
