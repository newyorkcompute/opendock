import Foundation
import Testing

@testable import DockCore

@Suite("Holding the pointer at the edge of a full-screen Space")
struct EdgeHoldTests {
    private let duration = EdgeHold.duration

    @Test func arrivingAtTheEdgeStartsAHold() {
        var hold = EdgeHold()
        #expect(hold.pointerMoved(atEdge: true, now: 10) == .began)
        #expect(hold.isHolding)
        #expect(hold.startedAt == 10)
    }

    @Test func movingAwayFromTheEdgeDoesNothing() {
        var hold = EdgeHold()
        #expect(hold.pointerMoved(atEdge: false, now: 10) == .none)
        #expect(hold.pointerMoved(atEdge: false, now: 11) == .none)
        #expect(!hold.isHolding)
    }

    @Test func brushingTheEdgeIsCancelled() {
        var hold = EdgeHold()
        #expect(hold.pointerMoved(atEdge: true, now: 10) == .began)
        #expect(hold.pointerMoved(atEdge: false, now: 10.1) == .ended)
        #expect(!hold.isHolding)
        #expect(!hold.isComplete(now: 10 + duration))
    }

    @Test func movingAlongTheEdgeKeepsTheHoldGoing() {
        var hold = EdgeHold()
        #expect(hold.pointerMoved(atEdge: true, now: 10) == .began)
        #expect(hold.pointerMoved(atEdge: true, now: 10.2) == .none)
        #expect(hold.pointerMoved(atEdge: true, now: 10.4) == .none)
        #expect(hold.startedAt == 10, "jitter along the edge doesn't restart the hold")
        #expect(hold.isComplete(now: 10 + duration))
    }

    @Test func completesOnlyAfterTheFullDuration() {
        var hold = EdgeHold()
        _ = hold.pointerMoved(atEdge: true, now: 10)
        #expect(!hold.isComplete(now: 10))
        #expect(!hold.isComplete(now: 10 + duration / 2))
        #expect(hold.isComplete(now: 10 + duration))
        #expect(hold.isComplete(now: 10 + duration * 3))
    }

    @Test func neverCompletesWithoutAHold() {
        let hold = EdgeHold()
        #expect(!hold.isComplete(now: 1000))
    }

    @Test func returningToTheEdgeStartsOver() {
        var hold = EdgeHold()
        _ = hold.pointerMoved(atEdge: true, now: 10)
        _ = hold.pointerMoved(atEdge: false, now: 10.3)
        #expect(hold.pointerMoved(atEdge: true, now: 10.4) == .began)
        #expect(hold.startedAt == 10.4)
        #expect(!hold.isComplete(now: 10 + duration), "time spent before leaving doesn't count")
        #expect(hold.isComplete(now: 10.4 + duration))
    }

    @Test func resetForgetsTheHold() {
        var hold = EdgeHold()
        _ = hold.pointerMoved(atEdge: true, now: 10)
        hold.reset()
        #expect(!hold.isHolding)
        #expect(!hold.isComplete(now: 10 + duration))
        // The pointer is still at the edge, but a fresh hold needs it to come back.
        #expect(hold.pointerMoved(atEdge: true, now: 10 + duration) == .began)
    }

    @Test func durationIsAShortHoldLikeApplesDock() {
        #expect(duration >= 0.3 && duration <= 1.0)
    }
}

@Suite("Full-screen reveal setting persistence")
struct FullScreenRevealSettingTests {
    private let decoder = JSONDecoder()

    @Test func defaultsToOn() throws {
        #expect(DockSettings.default.revealInFullScreen)
        #expect(try decoder.decode(DockSettings.self, from: Data("{}".utf8)).revealInFullScreen)
    }

    @Test func toleratesBadValues() throws {
        #expect(
            try decoder.decode(DockSettings.self, from: Data(#"{"revealInFullScreen": "no"}"#.utf8)).revealInFullScreen)
    }

    @Test func roundTrips() throws {
        var settings = DockSettings.default
        settings.revealInFullScreen = false
        let decoded = try decoder.decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.revealInFullScreen == false)
    }
}
