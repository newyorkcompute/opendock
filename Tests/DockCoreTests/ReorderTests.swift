import Foundation
import Testing
@testable import DockCore

@Suite("Drag reordering geometry")
struct ReorderTests {
    private let pitch = 60.0

    /// Pointer over the middle of the gap when it stands at `index` in a row of `count`
    /// icons (plus the gap), relative to the row's center.
    private func pointerOverGap(at index: Int, count: Int) -> Double {
        let rowWidth = Double(count + 1) * pitch
        return (Double(index) + 0.5) * pitch - rowWidth / 2
    }

    private func index(_ pointer: Double, count: Int = 4, limit: Int? = nil) -> Int {
        DockReorder.insertionIndex(
            pointer: pointer,
            slots: Array(repeating: pitch, count: count),
            gapWidth: pitch,
            limit: limit ?? count
        )
    }

    @Test func pointerOverGapKeepsItThere() {
        // The insertion point under the pointer is where the gap already is, at every index:
        // opening the gap never moves it out from under the pointer.
        for gap in 0...4 {
            #expect(index(pointerOverGap(at: gap, count: 4)) == gap)
        }
    }

    @Test func leavingTheGapMovesIt() {
        // Gap at 1 spans [60, 120) of a 300-wide row; it moves as soon as the pointer
        // crosses either edge, and not before.
        let gapCenter = pointerOverGap(at: 1, count: 4)
        #expect(index(gapCenter + pitch / 2 - 1) == 1)
        #expect(index(gapCenter + pitch / 2 + 1) == 2)
        #expect(index(gapCenter - pitch / 2 + 1) == 1)
        #expect(index(gapCenter - pitch / 2 - 1) == 0)
    }

    @Test func clampsBeyondTheEnds() {
        #expect(index(-10_000) == 0)
        #expect(index(10_000) == 4)
        #expect(index(0, count: 0) == 0)
    }

    @Test func limitKeepsDropsOutOfTrailingSlots() {
        // Five slots, but only the first three (pinned items) take drops.
        #expect(index(10_000, count: 5, limit: 3) == 3)
        #expect(index(pointerOverGap(at: 4, count: 5), count: 5, limit: 3) == 3)
        #expect(index(pointerOverGap(at: 2, count: 5), count: 5, limit: 3) == 2)
        #expect(index(0, count: 5, limit: -1) == 0)
    }

    @Test func reorderAtRestMapsToOwnSlot() {
        // Dragging item 2 of 5 out of its slot: the gap replaces it at the same width, so a
        // pointer still over the item's original place inserts it right back.
        let widths = [60.0, 40, 60, 90, 60]
        let dragged = 2
        var remaining = widths
        remaining.remove(at: dragged)
        let rowWidth = widths.reduce(0, +)
        let originalCenter = widths[..<dragged].reduce(0, +) + widths[dragged] / 2 - rowWidth / 2
        let result = DockReorder.insertionIndex(
            pointer: originalCenter,
            slots: remaining,
            gapWidth: widths[dragged],
            limit: remaining.count
        )
        #expect(result == dragged)
    }

    @Test func unevenSlotsSwitchAtTheirCenters() {
        // A narrow spacer (20) between icons. Measured without the gap (pointer less half
        // the gap), the gap passes each slot at that slot's center: 30, 70, 110.
        let slots = [60.0, 20, 60]
        let gap = 60.0
        let rowWidth = slots.reduce(0, +) + gap
        func at(_ x: Double) -> Int {
            DockReorder.insertionIndex(pointer: x + gap / 2 - rowWidth / 2, slots: slots, gapWidth: gap, limit: 3)
        }
        #expect(at(69) == 1)
        #expect(at(71) == 2)
        #expect(at(109) == 2)
        #expect(at(111) == 3)
    }

    @Test func gapAtIntegerPositionIsOnePiece() {
        #expect(DockReorder.gapPieces(position: 3, width: 60) == [.init(index: 3, width: 60)])
        #expect(DockReorder.gapPieces(position: 0, width: 60) == [.init(index: 0, width: 60)])
        #expect(DockReorder.gapPieces(position: -2, width: 60) == [.init(index: 0, width: 60)])
    }

    @Test func movingGapSplitsBetweenNeighbors() {
        let pieces = DockReorder.gapPieces(position: 1.25, width: 60)
        #expect(pieces == [.init(index: 1, width: 45), .init(index: 2, width: 15)])
        // The total never changes, so the row's width holds steady while the gap moves.
        for step in 0...20 {
            let total = DockReorder.gapPieces(position: Double(step) / 10, width: 60).map(\.width).reduce(0, +)
            #expect(abs(total - 60) < 1e-9)
        }
    }

    @Test func closedGapHasNoPieces() {
        #expect(DockReorder.gapPieces(position: 2, width: 0).isEmpty)
    }
}
