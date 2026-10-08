import Foundation
import Testing

@testable import DockCore

/// Where items added from a context menu or the Settings list go.
@Suite("Menu insertion index")
struct MenuInsertionTests {
    /// Four 50-point slots: the row spans -100 ... 100 around its center.
    private let fourSlots: [Double] = [50, 50, 50, 50]

    private func index(after anchor: Int? = nil, pointer: Double? = nil, slots: [Double]? = nil, limit: Int? = nil)
        -> Int
    {
        let slots = slots ?? fourSlots
        return DockReorder.menuInsertionIndex(
            afterItemAt: anchor, pointer: pointer, slots: slots, limit: limit ?? slots.count)
    }

    @Test func appendsWithoutAnchorOrPointer() {
        #expect(index() == 4)
        #expect(index(slots: [], limit: 0) == 0)
    }

    @Test func goesRightAfterTheItemWhoseMenuItWas() {
        #expect(index(after: 0) == 1)
        #expect(index(after: 1, pointer: -95) == 2) // the item wins over the pointer
        #expect(index(after: 3) == 4)
    }

    @Test func clampsAnchorToPinnedItems() {
        #expect(index(after: 9) == 4)
        #expect(index(after: 4, slots: [50, 50, 50, 50, 50, 50], limit: 4) == 4)
        #expect(index(after: -3) == 0)
    }

    @Test func picksTheGapNearestThePointer() {
        #expect(index(pointer: -500) == 0)
        #expect(index(pointer: -90) == 0) // left half of the first item
        #expect(index(pointer: -60) == 1) // right half of the first item
        #expect(index(pointer: -40) == 1) // left half of the second
        #expect(index(pointer: 0) == 2) // between the second and third
        #expect(index(pointer: 30) == 3)
        #expect(index(pointer: 95) == 4)
        #expect(index(pointer: 500) == 4)
    }

    @Test func respectsUnevenSlots() {
        // An icon, a narrow divider, an icon: -60 ... 60, centers at -35, 0, 35.
        let slots: [Double] = [50, 20, 50]
        #expect(index(pointer: -36, slots: slots) == 0)
        #expect(index(pointer: -34, slots: slots) == 1)
        #expect(index(pointer: -1, slots: slots) == 1)
        #expect(index(pointer: 1, slots: slots) == 2)
        #expect(index(pointer: 36, slots: slots) == 3)
    }

    @Test func neverLandsAmongUnpinnedRunningApps() {
        // Three pinned items, then the running-apps divider and one running app.
        let slots: [Double] = [50, 50, 50, 20, 50]
        #expect(index(pointer: 100, slots: slots, limit: 3) == 3)
        #expect(index(pointer: -100, slots: slots, limit: 3) == 0)
    }

    @Test func profileIndexAfterItem() {
        let items: [DockItem] = [.spacer(), .divider(), .spacer()]
        let profile = DockProfile(name: "P", items: items)
        #expect(profile.index(after: items[0].id) == 1)
        #expect(profile.index(after: items[2].id) == 3)
        #expect(profile.index(after: nil) == 3)
        #expect(profile.index(after: UUID()) == 3)
    }
}
