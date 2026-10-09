import Foundation
import Testing

@testable import SystemServices

@Suite("Refresh throttle")
struct RefreshThrottleTests {
    /// Which of a sequence of (force, seconds after start) refreshes the throttle lets through.
    private func admitted(_ attempts: [(force: Bool, seconds: Double)]) -> [Bool] {
        var throttle = RefreshThrottle()
        let start = ContinuousClock.now
        return attempts.map { throttle.admit(force: $0.force, now: start + .milliseconds($0.seconds * 1_000)) }
    }

    @Test func theFirstRefreshAlwaysGoesThrough() {
        #expect(admitted([(false, 0)]) == [true])
    }

    @Test func refreshesWithinFiveSecondsAreDropped() {
        #expect(
            admitted([(false, 0), (false, 1), (false, 4.999), (false, 5), (false, 6)]) == [
                true, false, false, true, false,
            ])
    }

    @Test func aForcedRefreshGoesThroughAndRestartsTheInterval() {
        #expect(admitted([(false, 0), (true, 1), (false, 5), (false, 6)]) == [true, true, false, true])
    }
}
