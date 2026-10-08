import Foundation
import Testing
@testable import DockCore

@Suite("Launch bounce timing")
struct LaunchBounceTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private let hop = LaunchBounce.hopDuration

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func hopTakesAboutAsLongAsAppleDocks() {
        #expect((0.6 ... 0.7).contains(hop))
    }

    @Test func hopsFollowGravity() {
        let bounce = LaunchBounce(start: start)
        #expect(bounce.lift(at: start) == 0)
        #expect(abs(bounce.lift(at: at(hop / 2)) - 1) < 1e-9)
        #expect(abs(bounce.lift(at: at(hop)) - 0) < 1e-9)
        // A parabola: symmetric about the top, and three quarters up at a quarter of the hop.
        #expect(abs(bounce.lift(at: at(hop / 4)) - 0.75) < 1e-9)
        #expect(abs(bounce.lift(at: at(hop * 0.3)) - bounce.lift(at: at(hop * 0.7))) < 1e-9)
        // Every hop is the same.
        #expect(abs(bounce.lift(at: at(hop * 3.25)) - bounce.lift(at: at(hop * 0.25))) < 1e-9)
    }

    @Test func fastestNearTheGroundAndSlowestAtTheTop() {
        let bounce = LaunchBounce(start: start)
        let step = hop / 20
        let leaving = bounce.lift(at: at(step)) - bounce.lift(at: start)
        let hanging = bounce.lift(at: at(hop / 2)) - bounce.lift(at: at(hop / 2 - step))
        #expect(leaving > 5 * hanging)
    }

    @Test func offsetScalesWithTheIconAsDrawn() {
        let bounce = LaunchBounce(start: start)
        let top = at(hop / 2)
        #expect(abs(bounce.offset(at: top, iconHeight: 48) - LaunchBounce.peakOffset(iconHeight: 48)) < 1e-9)
        #expect(abs(bounce.offset(at: top, iconHeight: 96) - 2 * bounce.offset(at: top, iconHeight: 48)) < 1e-9)
        #expect(LaunchBounce.peakOffset(iconHeight: 64) == LaunchBounce.hopHeight * 64)
    }

    @Test func nothingBeforeTheStart() {
        let bounce = LaunchBounce(start: start)
        #expect(bounce.lift(at: at(-0.1)) == 0)
    }

    @Test func keepsBouncingWhileLaunching() {
        let bounce = LaunchBounce(start: start)
        #expect(!bounce.isOver(at: at(10)))
        #expect(bounce.lift(at: at(10 * hop + hop / 2)) > 0.99)
    }

    @Test func landsAtTheEndOfTheHopInTheAirWhenTheLaunchEnds() {
        var bounce = LaunchBounce(start: start)
        bounce.launchEnded(at: at(2.4 * hop))
        #expect(bounce.hopCount == 3)
        #expect(abs(bounce.end.timeIntervalSince(at(3 * hop))) < 1e-9)
        // Still finishing the third hop after the launch ended...
        #expect(bounce.lift(at: at(2.5 * hop)) > 0.99)
        #expect(!bounce.isOver(at: at(2.9 * hop)))
        // ...then on the ground for good.
        #expect(bounce.isOver(at: at(3 * hop)))
        #expect(bounce.lift(at: at(3.5 * hop)) == 0)
    }

    @Test func launchEndingOnALandingStartsNoNewHop() {
        var bounce = LaunchBounce(start: start)
        bounce.launchEnded(at: at(2 * hop))
        #expect(bounce.hopCount == 2)
    }

    @Test func alwaysMakesAtLeastOneHop() {
        var bounce = LaunchBounce(start: start)
        bounce.launchEnded(at: start)
        #expect(bounce.hopCount == 1)
        #expect(bounce.lift(at: at(hop / 2)) > 0.99)

        var early = LaunchBounce(start: start)
        early.launchEnded(at: at(-1))
        #expect(early.hopCount == 1)
    }

    @Test func firstLaunchEndCounts() {
        var bounce = LaunchBounce(start: start)
        bounce.launchEnded(at: at(0.5 * hop))
        bounce.launchEnded(at: at(5.5 * hop))
        #expect(bounce.hopCount == 1)
    }

    @Test func givesUpAfterTheTimeout() {
        let bounce = LaunchBounce(start: start)
        #expect(bounce.hopCount == LaunchBounce.maximumHops)
        let end = bounce.end.timeIntervalSince(start)
        #expect(end >= LaunchBounce.timeout)
        #expect(end < LaunchBounce.timeout + hop)
        #expect(bounce.isOver(at: at(end)))
        #expect(bounce.lift(at: at(end + hop / 2)) == 0)

        var late = LaunchBounce(start: start)
        late.launchEnded(at: at(LaunchBounce.timeout * 3))
        #expect(late.end == bounce.end)
    }

    @Test func timeoutIsSensible() {
        #expect((10 ... 30).contains(LaunchBounce.timeout))
    }

    @Test func reducedMotionFadesInsteadOfMoving() {
        let bounce = LaunchBounce(start: start)
        #expect(bounce.reducedMotionOpacity(at: start) == 1)
        #expect(abs(bounce.reducedMotionOpacity(at: at(hop / 2)) - (1 - LaunchBounce.reducedMotionFade)) < 1e-9)
        #expect(bounce.reducedMotionOpacity(at: at(LaunchBounce.timeout + hop)) == 1)
        #expect(LaunchBounce.reducedMotionFade < 1)
    }
}

@Suite("Launch bounces in the dock")
struct LaunchBouncesTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private let hop = LaunchBounce.hopDuration
    private let safari = AppItem(url: URL(filePath: "/Applications/Safari.app"), bundleIdentifier: "com.apple.Safari")
    private let notes = AppItem(url: URL(filePath: "/System/Applications/Notes.app"), bundleIdentifier: "com.apple.Notes")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func startsOncePerApp() {
        var bounces = LaunchBounces()
        let started = bounces.start(safari, at: start)
        let restarted = bounces.start(safari, at: at(1))
        #expect(started)
        #expect(!restarted)
        #expect(bounces.bounce(for: safari)?.start == start)
        #expect(bounces.bounce(for: notes) == nil)
    }

    @Test func findsTheAppByBundleIdentifierOrPath() {
        var bounces = LaunchBounces()
        bounces.start(safari, at: start)
        let otherCopy = AppItem(url: URL(filePath: "/Users/me/Downloads/Safari.app"), bundleIdentifier: "com.apple.Safari")
        let samePath = AppItem(url: URL(filePath: "/Applications/Safari.app/"), bundleIdentifier: nil)
        let unrelated = AppItem(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.example.other")
        #expect(bounces.bounce(for: otherCopy) != nil)
        #expect(bounces.bounce(for: samePath) != nil)
        #expect(bounces.bounce(for: unrelated) == nil)
    }

    @Test func eachAppLandsOnItsOwn() {
        var bounces = LaunchBounces()
        bounces.start(safari, at: start)
        bounces.start(notes, at: at(0.1))
        bounces.launchEnded(safari, at: at(0.3))
        #expect(bounces.bounce(for: safari)?.hopCount == 1)
        #expect(bounces.bounce(for: notes)?.launchEnd == nil)
        #expect(bounces.nextEnd == at(hop))
    }

    @Test func removesFinishedBounces() throws {
        var bounces = LaunchBounces()
        bounces.start(safari, at: start)
        bounces.start(notes, at: start)
        bounces.launchEnded(safari, at: at(0.1))
        let midHop = bounces.removeFinished(at: at(hop / 2))
        #expect(midHop.isEmpty)
        let landed = bounces.removeFinished(at: at(hop))
        #expect(landed == [safari])
        #expect(bounces.bounce(for: safari) == nil)
        #expect(bounces.bounce(for: notes) != nil)
        // The one that never finished launching is dropped at the timeout.
        let timeout = try #require(bounces.nextEnd)
        #expect(timeout == bounces.bounce(for: notes)?.end)
        let timedOut = bounces.removeFinished(at: timeout)
        #expect(timedOut == [notes])
        #expect(bounces.isEmpty)
        #expect(bounces.nextEnd == nil)
    }

    @Test func launchEndForAnAppNotBouncingIsIgnored() {
        var bounces = LaunchBounces()
        bounces.start(safari, at: start)
        bounces.launchEnded(notes, at: at(0.1))
        #expect(bounces.bounce(for: safari)?.launchEnd == nil)
    }
}
