import Foundation
import Testing

@testable import DockCore

@Suite("Stopwatch")
struct StopwatchTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)

    @Test func startsAtZero() {
        let stopwatch = Stopwatch()
        #expect(!stopwatch.hasStarted)
        #expect(!stopwatch.isRunning)
        #expect(stopwatch.elapsed(at: t0) == 0)
        #expect(stopwatch.laps.isEmpty)
    }

    @Test func runsFromTheStart() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: t0)
        #expect(stopwatch.isRunning)
        #expect(stopwatch.hasStarted)
        #expect(stopwatch.elapsed(at: t0 + 12.5) == 12.5)
        #expect(stopwatch.elapsed(at: t0 - 1) == 0, "a clock stepping back never reads negative")
    }

    @Test func stoppingFreezesTheTimeAndStartingResumesIt() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: t0)
        stopwatch.stop(at: t0 + 10)
        #expect(!stopwatch.isRunning)
        #expect(stopwatch.hasStarted)
        #expect(stopwatch.elapsed(at: t0 + 100) == 10)
        stopwatch.start(at: t0 + 100)
        #expect(stopwatch.elapsed(at: t0 + 105) == 15)
    }

    @Test func toggleStartsAndStops() {
        var stopwatch = Stopwatch()
        stopwatch.toggle(at: t0)
        #expect(stopwatch.isRunning)
        stopwatch.toggle(at: t0 + 3)
        #expect(!stopwatch.isRunning)
        #expect(stopwatch.elapsed(at: t0 + 9) == 3)
    }

    @Test func redundantStartsAndStopsDoNothing() {
        var stopwatch = Stopwatch()
        stopwatch.stop(at: t0)
        #expect(!stopwatch.hasStarted)
        stopwatch.start(at: t0)
        stopwatch.start(at: t0 + 5)
        #expect(stopwatch.elapsed(at: t0 + 10) == 10, "starting again doesn't restart")
    }

    @Test func lapsRecordTheirOwnLengthAndTheTotal() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: t0)
        let first = stopwatch.lap(at: t0 + 10)
        #expect(first == Stopwatch.Lap(number: 1, duration: 10, total: 10))
        let second = stopwatch.lap(at: t0 + 25)
        #expect(second == Stopwatch.Lap(number: 2, duration: 15, total: 25))
        #expect(stopwatch.laps.map(\.number) == [1, 2])
        #expect(stopwatch.currentLap(at: t0 + 30) == 5)
    }

    @Test func lapsNeedARunningStopwatch() {
        var stopwatch = Stopwatch()
        #expect(stopwatch.lap(at: t0) == nil)
        stopwatch.start(at: t0)
        stopwatch.stop(at: t0 + 4)
        #expect(stopwatch.lap(at: t0 + 5) == nil)
        #expect(stopwatch.laps.isEmpty)
    }

    @Test func fastestAndSlowestNeedTwoLaps() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: t0)
        stopwatch.lap(at: t0 + 10)
        #expect(stopwatch.fastestLap == nil)
        #expect(stopwatch.slowestLap == nil)
        stopwatch.lap(at: t0 + 14)
        stopwatch.lap(at: t0 + 30)
        #expect(stopwatch.fastestLap?.number == 2)
        #expect(stopwatch.slowestLap?.number == 3)
    }

    @Test func resetClearsEverything() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: t0)
        stopwatch.lap(at: t0 + 1)
        stopwatch.reset()
        #expect(stopwatch == Stopwatch())
        #expect(stopwatch.elapsed(at: t0 + 50) == 0)
    }
}
