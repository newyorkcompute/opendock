import CoreGraphics
import Foundation

/// The direction the dock's items are lined up in: along the bottom edge, or up a side.
public enum DockAxis: Hashable, Sendable {
    case horizontal
    case vertical

    /// A point's coordinate on the axis.
    public func along(_ point: CGPoint) -> CGFloat {
        self == .vertical ? point.y : point.x
    }

    /// How far a size extends on the axis.
    public func length(of size: CGSize) -> CGFloat {
        self == .vertical ? size.height : size.width
    }

    /// How far a size extends across the axis.
    public func thickness(of size: CGSize) -> CGFloat {
        self == .vertical ? size.width : size.height
    }

    /// A size that extends `length` on the axis and `thickness` across it.
    public func size(length: CGFloat, thickness: CGFloat) -> CGSize {
        self == .vertical ? CGSize(width: thickness, height: length) : CGSize(width: length, height: thickness)
    }

    /// Where a rectangle starts and ends on the axis.
    public func span(of rect: CGRect) -> ClosedRange<CGFloat> {
        self == .vertical ? rect.minY ... rect.maxY : rect.minX ... rect.maxX
    }
}

/// The dock's own frame of reference, which is the same on every edge: positions run
/// *along* the screen edge, and *depth* measures how far something is from that edge,
/// toward the middle of the screen. Converts to and from a container in layout
/// coordinates (origin at the top left, y down) whose side on `edge` touches the screen
/// edge. Pure math, so the layout can be unit tested on every edge.
public struct DockEdgeSpace: Hashable, Sendable {
    public var edge: DockSettings.Edge
    public var bounds: CGRect

    public init(edge: DockSettings.Edge, bounds: CGRect) {
        self.edge = edge
        self.bounds = bounds
    }

    public var axis: DockAxis { edge.axis }

    /// Where the container starts and ends along the edge.
    public var span: ClosedRange<CGFloat> { axis.span(of: bounds) }

    /// Halfway along the container.
    public var middle: CGFloat { (span.lowerBound + span.upperBound) / 2 }

    /// How far the container reaches from the screen edge.
    public var depth: CGFloat { axis.thickness(of: bounds.size) }

    /// `point`'s position along the edge.
    public func along(_ point: CGPoint) -> CGFloat {
        axis.along(point)
    }

    /// How far `point` is from the screen edge.
    public func depth(of point: CGPoint) -> CGFloat {
        switch edge {
        case .bottom: bounds.maxY - point.y
        case .left: point.x - bounds.minX
        case .right: bounds.maxX - point.x
        }
    }

    /// The rectangle that starts at `along` and runs `length` along the edge, and starts
    /// `depth` from the screen edge and reaches `thickness` further from it.
    public func rect(along: CGFloat, length: CGFloat, depth: CGFloat, thickness: CGFloat) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: along, y: bounds.maxY - depth - thickness, width: length, height: thickness)
        case .left: CGRect(x: bounds.minX + depth, y: along, width: thickness, height: length)
        case .right: CGRect(x: bounds.maxX - depth - thickness, y: along, width: thickness, height: length)
        }
    }

    /// How far `rect`'s near side, the one toward the screen edge, is from that edge.
    public func nearDepth(of rect: CGRect) -> CGFloat {
        switch edge {
        case .bottom: bounds.maxY - rect.maxY
        case .left: rect.minX - bounds.minX
        case .right: bounds.maxX - rect.maxX
        }
    }

    /// How far `rect`'s far side, the one toward the middle of the screen, is from the edge.
    public func farDepth(of rect: CGRect) -> CGFloat {
        switch edge {
        case .bottom: bounds.maxY - rect.minY
        case .left: rect.maxX - bounds.minX
        case .right: bounds.maxX - rect.minX
        }
    }

    /// The middle of `rect`'s near side: where an item is anchored, so that magnified it
    /// grows away from the screen edge and along it, never toward the edge.
    public func anchor(of rect: CGRect) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        }
    }
}
