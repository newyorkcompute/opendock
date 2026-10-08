import Foundation
import Testing

@testable import DockCore

@Suite("Folder arrivals")
struct FolderArrivalsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func theFirstCountIsOnlyABaseline() {
        var arrivals = FolderArrivals()
        #expect(!arrivals.update(count: 12, at: start))
        #expect(!arrivals.update(count: 12, at: start + 5))
    }

    @Test func moreEntriesMeansAnArrival() {
        var arrivals = FolderArrivals()
        _ = arrivals.update(count: 3, at: start)
        #expect(arrivals.update(count: 4, at: start + 5))
    }

    @Test func fewerEntriesIsNotAnArrival() {
        var arrivals = FolderArrivals()
        _ = arrivals.update(count: 3, at: start)
        #expect(!arrivals.update(count: 2, at: start + 5))
        #expect(!arrivals.update(count: 2, at: start + 10))
        #expect(arrivals.update(count: 3, at: start + 15))
    }

    @Test func arrivalsInQuickSuccessionHopOnce() {
        var arrivals = FolderArrivals()
        _ = arrivals.update(count: 0, at: start)
        #expect(arrivals.update(count: 1, at: start + 5))
        #expect(!arrivals.update(count: 2, at: start + 5 + FolderArrivals.quietPeriod / 2))
        #expect(arrivals.update(count: 3, at: start + 5 + FolderArrivals.quietPeriod + 0.1))
    }
}
