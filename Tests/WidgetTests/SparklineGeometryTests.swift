import DockWidgetKit
import Foundation
import Testing

@MainActor
@Suite("Sparkline geometry")
struct SparklineGeometryTests {
    private let size = CGSize(width: 40, height: 11)

    @Test func newestSampleSitsAtTheRightEdge() {
        let points = SparklineGeometry.points(for: [0, 1, 0.5], capacity: 5, in: size)
        #expect(points.map(\.x) == [20, 30, 40])
    }

    @Test func fullHistorySpansTheWidth() {
        let points = SparklineGeometry.points(for: [0, 0, 0, 0, 0], capacity: 5, in: size)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 40)
    }

    @Test func leavesTheBottomRowForTheBaseline() {
        let points = SparklineGeometry.points(for: [0, 1, 0.5], capacity: 5, in: size)
        #expect(points.map(\.y) == [10, 0, 5])
    }

    @Test func clampsSamplesToTheUnitRange() {
        let points = SparklineGeometry.points(for: [-3, 7], capacity: 2, in: size)
        #expect(points.map(\.y) == [10, 0])
    }

    @Test func handlesDegenerateInput() {
        #expect(SparklineGeometry.points(for: [], capacity: 60, in: size).isEmpty)
        #expect(SparklineGeometry.points(for: [1], capacity: 0, in: size).map(\.x) == [40])
        #expect(SparklineGeometry.line(through: []).isEmpty)
        #expect(SparklineGeometry.area(under: [], in: size).isEmpty)
    }

    @Test func areaReachesTheBottomEdgeAndLineDoesNot() {
        let points = SparklineGeometry.points(for: [0.5, 1, 0.5], capacity: 3, in: size)
        let area = SparklineGeometry.area(under: points, in: size).boundingRect
        let line = SparklineGeometry.line(through: points).boundingRect
        #expect(area.maxY == size.height)
        #expect(area.minX == 0 && area.maxX == size.width)
        #expect(line.maxY == 5 && line.minY == 0)
    }
}
