import CoreGraphics
import Foundation
import Testing

@testable import DockCore

@Suite("Dock axis")
struct DockAxisTests {
    @Test func edgesKnowTheirAxis() {
        #expect(DockSettings.Edge.bottom.axis == .horizontal)
        #expect(DockSettings.Edge.left.axis == .vertical)
        #expect(DockSettings.Edge.right.axis == .vertical)
        #expect(!DockSettings.Edge.bottom.isVertical)
        #expect(DockSettings.Edge.left.isVertical)
        #expect(DockSettings.Edge.right.isVertical)
    }

    @Test func horizontalMeasuresAlongX() {
        let axis = DockAxis.horizontal
        #expect(axis.along(CGPoint(x: 3, y: 7)) == 3)
        #expect(axis.length(of: CGSize(width: 10, height: 20)) == 10)
        #expect(axis.thickness(of: CGSize(width: 10, height: 20)) == 20)
        #expect(axis.size(length: 10, thickness: 20) == CGSize(width: 10, height: 20))
        #expect(axis.span(of: CGRect(x: 5, y: 50, width: 10, height: 20)) == 5 ... 15)
    }

    @Test func verticalMeasuresAlongY() {
        let axis = DockAxis.vertical
        #expect(axis.along(CGPoint(x: 3, y: 7)) == 7)
        #expect(axis.length(of: CGSize(width: 10, height: 20)) == 20)
        #expect(axis.thickness(of: CGSize(width: 10, height: 20)) == 10)
        #expect(axis.size(length: 10, thickness: 20) == CGSize(width: 20, height: 10))
        #expect(axis.span(of: CGRect(x: 5, y: 50, width: 10, height: 20)) == 50 ... 70)
    }

    @Test func sizeRoundTrips() {
        let size = CGSize(width: 150, height: 54)
        for axis in [DockAxis.horizontal, .vertical] {
            #expect(axis.size(length: axis.length(of: size), thickness: axis.thickness(of: size)) == size)
        }
    }
}

@Suite("Dock edge space")
struct EdgeSpaceTests {
    /// A container 400 along by 100 deep, laid out in SwiftUI's coordinates (y down),
    /// placed away from the origin so offsets show up.
    private func space(_ edge: DockSettings.Edge) -> DockEdgeSpace {
        let bounds =
            edge.isVertical
            ? CGRect(x: 10, y: 20, width: 100, height: 400) : CGRect(x: 10, y: 20, width: 400, height: 100)
        return DockEdgeSpace(edge: edge, bounds: bounds)
    }

    @Test func spanAndDepthDescribeTheContainer() {
        for edge in DockSettings.Edge.allCases {
            let space = space(edge)
            #expect(space.depth == 100, "\(edge)")
            #expect(space.span.upperBound - space.span.lowerBound == 400, "\(edge)")
            #expect(space.middle == (space.span.lowerBound + space.span.upperBound) / 2, "\(edge)")
        }
        #expect(space(.bottom).span == 10 ... 410)
        #expect(space(.left).span == 20 ... 420)
    }

    @Test func rectsSitAgainstTheirEdge() {
        // 30 along, 50 long, starting 8 from the edge and reaching 40 further.
        #expect(
            space(.bottom).rect(along: 30, length: 50, depth: 8, thickness: 40)
                == CGRect(x: 30, y: 120 - 8 - 40, width: 50, height: 40))
        #expect(
            space(.left).rect(along: 30, length: 50, depth: 8, thickness: 40)
                == CGRect(x: 10 + 8, y: 30, width: 40, height: 50))
        #expect(
            space(.right).rect(along: 30, length: 50, depth: 8, thickness: 40)
                == CGRect(x: 110 - 8 - 40, y: 30, width: 40, height: 50))
    }

    @Test func depthsReadBackFromRects() {
        for edge in DockSettings.Edge.allCases {
            let space = space(edge)
            let rect = space.rect(along: 30, length: 50, depth: 8, thickness: 40)
            #expect(space.nearDepth(of: rect) == 8, "\(edge)")
            #expect(space.farDepth(of: rect) == 48, "\(edge)")
            #expect(space.axis.span(of: rect) == 30 ... 80, "\(edge)")
            // The anchor is on the near side, halfway along.
            let anchor = space.anchor(of: rect)
            #expect(space.depth(of: anchor) == 8, "\(edge)")
            #expect(space.along(anchor) == 55, "\(edge)")
        }
    }

    @Test func pointDepthIsDistanceFromTheScreenEdge() {
        #expect(space(.bottom).depth(of: CGPoint(x: 100, y: 120)) == 0)
        #expect(space(.bottom).depth(of: CGPoint(x: 100, y: 90)) == 30)
        #expect(space(.left).depth(of: CGPoint(x: 10, y: 100)) == 0)
        #expect(space(.left).depth(of: CGPoint(x: 40, y: 100)) == 30)
        #expect(space(.right).depth(of: CGPoint(x: 110, y: 100)) == 0)
        #expect(space(.right).depth(of: CGPoint(x: 80, y: 100)) == 30)
    }

    @Test func anchorsAreTheMiddleOfTheNearSide() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(space(.bottom).anchor(of: rect) == CGPoint(x: 25, y: 60))
        #expect(space(.left).anchor(of: rect) == CGPoint(x: 10, y: 40))
        #expect(space(.right).anchor(of: rect) == CGPoint(x: 40, y: 40))
    }

    /// The same row laid out on each edge lands in mirror-image places: an item's
    /// position along the edge and its depth don't depend on the edge.
    @Test func layoutIsTheSameOnEveryEdge() {
        var frames: [DockSettings.Edge: [(along: ClosedRange<CGFloat>, near: CGFloat, far: CGFloat)]] = [:]
        for edge in DockSettings.Edge.allCases {
            let space = space(edge)
            let row = DockMagnification.row(
                Array(repeating: .init(width: 54, growth: 1), count: 5), pointer: 135, peakScale: 1.5, radius: 162)
            let start = space.middle - 5 * 54 / 2
            frames[edge] = row.origins.indices.map { k in
                let length = 48 * row.scales[k]
                let rect = space.rect(
                    along: start + row.origins[k] + row.widths[k] / 2 - length / 2, length: length,
                    depth: 18, thickness: length + 6)
                let span = space.axis.span(of: rect)
                let offset = span.lowerBound - space.span.lowerBound
                return (
                    offset ... offset + (span.upperBound - span.lowerBound), space.nearDepth(of: rect),
                    space.farDepth(of: rect)
                )
            }
        }
        for k in 0 ..< 5 {
            for edge in [DockSettings.Edge.left, .right] {
                let reference = frames[.bottom]![k]
                let frame = frames[edge]![k]
                #expect(abs(frame.along.lowerBound - reference.along.lowerBound) < 1e-9, "\(edge) \(k)")
                #expect(abs(frame.along.upperBound - reference.along.upperBound) < 1e-9, "\(edge) \(k)")
                #expect(abs(frame.near - reference.near) < 1e-9, "\(edge) \(k)")
                #expect(abs(frame.far - reference.far) < 1e-9, "\(edge) \(k)")
            }
        }
    }
}

@Suite("Magnified item sizes on a side edge")
struct VerticalItemSizeTests {
    @Test func iconsGrowSquareAndKeepTheirIndicatorRoomBeside() {
        // An icon with the indicator beside it: 6 wider than it is tall.
        let icon = CGSize(width: 54, height: 48)
        let size = DockMagnification.itemSize(icon, scale: 1.5, iconSize: 48, axis: .vertical)
        #expect(size == CGSize(width: 78, height: 72))
    }

    @Test func tallTilesGrowInWidthLikeAnIconAndInHeightLikeTheirSlot() {
        let tile = CGSize(width: 54, height: 150)
        let size = DockMagnification.itemSize(tile, scale: 1.15, iconSize: 48, axis: .vertical)
        #expect(abs(size.height - 150 * 1.15) < 1e-9)
        #expect(abs(size.width - (54 + 48 * 0.15)) < 1e-9)
        // Across the dock, without the indicator room, the tile is the icon size times the scale.
        #expect(abs(DockMagnification.tileScale(height: size.width - 6, iconSize: 48) - 1.15) < 1e-9)
    }

    @Test func verticalIsTheHorizontalCaseTransposed() {
        let resting = CGSize(width: 150, height: 54)
        let transposed = CGSize(width: 54, height: 150)
        for scale in [1.0, 1.15, 1.5, 2.0] {
            let horizontal = DockMagnification.itemSize(resting, scale: scale, iconSize: 48)
            let vertical = DockMagnification.itemSize(transposed, scale: scale, iconSize: 48, axis: .vertical)
            #expect(vertical == CGSize(width: horizontal.height, height: horizontal.width), "\(scale)")
        }
    }

    @Test func horizontalIsTheDefaultAxis() {
        let tile = CGSize(width: 150, height: 54)
        #expect(
            DockMagnification.itemSize(tile, scale: 1.3, iconSize: 48)
                == DockMagnification.itemSize(tile, scale: 1.3, iconSize: 48, axis: .horizontal))
    }
}

@Suite("Edge setting persistence")
struct EdgeSettingTests {
    private func decode(_ json: String) throws -> DockSettings {
        try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
    }

    @Test func missingKeyMeansBottom() throws {
        #expect(try decode(#"{"iconSize": 40}"#).edge == .bottom)
        #expect(DockSettings.default.edge == .bottom)
    }

    @Test func roundTripsEveryEdge() throws {
        for edge in DockSettings.Edge.allCases {
            var settings = DockSettings.default
            settings.edge = edge
            let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
            #expect(decoded.edge == edge)
        }
    }

    @Test func decodesTheStoredShape() throws {
        #expect(try decode(#"{"edge": "left"}"#).edge == .left)
        #expect(try decode(#"{"edge": "right"}"#).edge == .right)
        #expect(try decode(#"{"edge": "bottom"}"#).edge == .bottom)
    }

    @Test func unrecognizedValuesFallBackWithoutLosingOtherSettings() throws {
        for json in [
            #"{"edge": "top", "iconSize": 40}"#, #"{"edge": 2, "iconSize": 40}"#, #"{"edge": null, "iconSize": 40}"#,
        ] {
            let settings = try decode(json)
            #expect(settings.edge == .bottom, "\(json)")
            #expect(settings.iconSize == 40, "\(json)")
        }
    }
}

@Suite("Profile swipe follows the dock's axis")
struct VerticalProfileScrollGestureTests {
    private func swipe(_ gesture: inout ProfileScrollGesture, deltaX: Double, deltaY: Double) -> Int? {
        var step = gesture.handle(.init(deltaX: 0, deltaY: 0, phase: .began, timestamp: 0))
        for i in 1 ... 4 {
            step =
                gesture.handle(.init(deltaX: deltaX, deltaY: deltaY, phase: .changed, timestamp: Double(i) * 0.02))
                ?? step
        }
        _ = gesture.handle(.init(deltaX: 0, deltaY: 0, phase: .ended, timestamp: 0.1))
        return step
    }

    @Test func sideDockSwitchesOnVerticalSwipes() {
        var gesture = ProfileScrollGesture(axis: .vertical)
        #expect(swipe(&gesture, deltaX: 0, deltaY: -12) == 1)
        #expect(swipe(&gesture, deltaX: 0, deltaY: 12) == -1)
        // A sideways swipe is across a side dock, not along it.
        #expect(swipe(&gesture, deltaX: -12, deltaY: 0) == nil)
    }

    @Test func bottomDockStillSwitchesOnSidewaysSwipes() {
        var gesture = ProfileScrollGesture()
        #expect(gesture.axis == .horizontal)
        #expect(swipe(&gesture, deltaX: -12, deltaY: 0) == 1)
        #expect(swipe(&gesture, deltaX: 0, deltaY: -12) == nil)
    }

    @Test func verticalWheelSwitchesASideDock() {
        var gesture = ProfileScrollGesture(axis: .vertical)
        #expect(gesture.handle(.init(deltaX: 0, deltaY: -3, phase: .none, timestamp: 1)) == 1)
        #expect(gesture.handle(.init(deltaX: -3, deltaY: 0, phase: .none, timestamp: 2)) == nil)
        #expect(gesture.handle(.init(deltaX: -3, deltaY: 0, phase: .none, isCommandDown: true, timestamp: 3)) == 1)
    }
}
