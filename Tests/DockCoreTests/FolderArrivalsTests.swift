import Foundation
import Testing

@testable import DockCore

@Suite("Folder arrivals")
struct FolderArrivalsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    /// Feeds `counts` (entry count and seconds after `start`) in order and returns which
    /// of them hopped the icon.
    private func hops(_ counts: [(count: Int, after: TimeInterval)]) -> [Bool] {
        var arrivals = FolderArrivals()
        return counts.map { arrivals.update(count: $0.count, at: start + $0.after) }
    }

    @Test func theFirstCountIsOnlyABaseline() {
        #expect(hops([(12, 0), (12, 5)]) == [false, false])
    }

    @Test func moreEntriesMeansAnArrival() {
        #expect(hops([(3, 0), (4, 5)]) == [false, true])
    }

    @Test func fewerEntriesIsNotAnArrival() {
        #expect(hops([(3, 0), (2, 5), (2, 10), (3, 15)]) == [false, false, false, true])
    }

    @Test func arrivalsInQuickSuccessionHopOnce() {
        let quiet = FolderArrivals.quietPeriod
        #expect(hops([(0, 0), (1, 5), (2, 5 + quiet / 2), (3, 5 + quiet + 0.1)]) == [false, true, false, true])
    }
}
