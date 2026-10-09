import Foundation
import Testing

@testable import DockCore

@Suite("Dragging the row's items")
struct RowDragTests {
    private typealias Drag = DockRowDrag

    // MARK: Placement

    @Test func pinnedItemsMoveAmongThePinnedItems() {
        for index in 0 ... 3 {
            #expect(Drag.placement(of: .pinned, insertionIndex: index, pinnedCount: 3, homeIndex: 1) == .insert(index))
        }
    }

    @Test func pinnedItemsStopAtTheEndOfThePinnedItems() {
        // Past the pinned items (over the running apps, say) the gap sits at their end.
        #expect(Drag.placement(of: .pinned, insertionIndex: 4, pinnedCount: 3, homeIndex: 1) == .insert(3))
        #expect(Drag.placement(of: .pinned, insertionIndex: 100, pinnedCount: 3, homeIndex: 1) == .insert(3))
        #expect(Drag.placement(of: .pinned, insertionIndex: -1, pinnedCount: 3, homeIndex: 1) == .insert(0))
    }

    @Test func sectionAppsPinOverThePinnedItems() {
        for item in [Drag.Item.running, .recent] {
            for index in 0 ... 3 {
                #expect(
                    Drag.placement(of: item, insertionIndex: index, pinnedCount: 3, homeIndex: 5) == .insert(index),
                    "\(item) at \(index)")
            }
        }
    }

    @Test func sectionAppsStayHomePastThePinnedItems() {
        // Over the sections after the pinned items the app can't land; its own slot waits.
        for item in [Drag.Item.running, .recent] {
            #expect(Drag.placement(of: item, insertionIndex: 4, pinnedCount: 3, homeIndex: 5) == .home(5))
            #expect(Drag.placement(of: item, insertionIndex: 100, pinnedCount: 3, homeIndex: 5) == .home(5))
        }
    }

    @Test func sectionAppsPinIntoAnEmptyProfile() {
        // No pinned items: only the very start of the row takes the app.
        #expect(Drag.placement(of: .running, insertionIndex: 0, pinnedCount: 0, homeIndex: 2) == .insert(0))
        #expect(Drag.placement(of: .running, insertionIndex: 1, pinnedCount: 0, homeIndex: 2) == .home(2))
    }

    @Test func placementNeverGoesNegative() {
        #expect(Drag.placement(of: .running, insertionIndex: -2, pinnedCount: 3, homeIndex: 5) == .insert(0))
        #expect(Drag.placement(of: .recent, insertionIndex: 9, pinnedCount: -1, homeIndex: -3) == .home(0))
        #expect(Drag.placement(of: .pinned, insertionIndex: 2, pinnedCount: -1, homeIndex: 0) == .insert(0))
    }

    // MARK: Dragging off the dock

    @Test func onlyPinnedAndRecentItemsArmARemoval() {
        #expect(Drag.removesWhenDraggedOff(.pinned))
        #expect(Drag.removesWhenDraggedOff(.recent))
        #expect(!Drag.removesWhenDraggedOff(.running), "a running app can't be dragged away")
    }

    @Test func armedRemovalsTakeTheirItemOut() {
        #expect(Drag.outcome(of: .pinned, at: .offDock(armed: true)) == .remove)
        #expect(Drag.outcome(of: .recent, at: .offDock(armed: true)) == .forgetRecent)
        #expect(Drag.outcome(of: .running, at: .offDock(armed: true)) == .refuse)
    }

    @Test func lettingGoOffTheDockBeforeArmingCancels() {
        for item in [Drag.Item.pinned, .running, .recent] {
            #expect(Drag.outcome(of: item, at: .offDock(armed: false)) == .cancel, "\(item)")
        }
    }

    // MARK: The Trash

    @Test func theTrashRemovesPinnedItemsAndForgetsRecents() {
        #expect(Drag.outcome(of: .pinned, at: .trash) == .remove)
        #expect(Drag.outcome(of: .recent, at: .trash) == .forgetRecent)
    }

    @Test func theTrashRefusesARunningApp() {
        #expect(Drag.outcome(of: .running, at: .trash) == .refuse)
    }

    // MARK: Drops in the row

    @Test func pinnedItemsMoveWhereTheGapIs() {
        #expect(Drag.outcome(of: .pinned, at: .row(.insert(2))) == .move(to: 2))
        #expect(Drag.outcome(of: .pinned, at: .row(.insert(0))) == .move(to: 0))
    }

    @Test func sectionAppsPinWhereTheGapIs() {
        #expect(Drag.outcome(of: .running, at: .row(.insert(1))) == .pin(at: 1))
        #expect(Drag.outcome(of: .recent, at: .row(.insert(3))) == .pin(at: 3))
    }

    @Test func droppingAtHomeDoesNothing() {
        for item in [Drag.Item.pinned, .running, .recent] {
            #expect(Drag.outcome(of: item, at: .row(.home(4))) == .cancel, "\(item)")
        }
    }

    @Test func nothingDestructiveEverHappensToARunningApp() {
        let targets: [Drag.Target] = [
            .row(.insert(0)), .row(.insert(5)), .row(.home(2)), .trash, .offDock(armed: false), .offDock(armed: true),
        ]
        for target in targets {
            let outcome = Drag.outcome(of: .running, at: target)
            #expect(outcome != .remove && outcome != .forgetRecent, "\(target)")
        }
    }

    @Test func placementsFeedStraightIntoOutcomes() {
        // The shell computes a placement while the drag is over the row and hands it back
        // when the drop lands; the two agree on what the gap promised.
        let placement = Drag.placement(of: .recent, insertionIndex: 2, pinnedCount: 3, homeIndex: 6)
        #expect(Drag.outcome(of: .recent, at: .row(placement)) == .pin(at: 2))
        let home = Drag.placement(of: .recent, insertionIndex: 5, pinnedCount: 3, homeIndex: 6)
        #expect(Drag.outcome(of: .recent, at: .row(home)) == .cancel)
    }
}
