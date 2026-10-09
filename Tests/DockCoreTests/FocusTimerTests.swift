import Foundation
import Testing

@testable import DockCore

@Suite("Focus timer")
struct FocusTimerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let plan = FocusTimer.Plan(
        focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, sessionsBeforeLongBreak: 4)

    @Test func startsIdleWithTheFullFocusSession() {
        let timer = FocusTimer(plan: plan)
        #expect(timer.isIdle)
        #expect(timer.phase == .focus)
        #expect(timer.remaining(at: t0) == 25 * 60)
        #expect(timer.fractionRemaining(at: t0) == 1)
        #expect(timer.sessionNumber == 1)
        #expect(!timer.isComplete(at: t0))
    }

    @Test func runningCountsDownFromTheStart() {
        var timer = FocusTimer(plan: plan)
        timer.start(at: t0)
        #expect(timer.isRunning)
        #expect(timer.remaining(at: t0 + 60) == 24 * 60)
        #expect(abs(timer.fractionRemaining(at: t0 + 12.5 * 60) - 0.5) < 0.0001)
        #expect(timer.remaining(at: t0 + 30 * 60) == 0, "never negative")
        #expect(timer.isComplete(at: t0 + 25 * 60))
        #expect(!timer.isComplete(at: t0 + 25 * 60 - 1))
    }

    @Test func pausingKeepsTheRemainingTime() {
        var timer = FocusTimer(plan: plan)
        timer.start(at: t0)
        timer.pause(at: t0 + 5 * 60)
        #expect(timer.isPaused)
        #expect(timer.remaining(at: t0 + 60 * 60) == 20 * 60, "a paused timer doesn't move")
        timer.start(at: t0 + 60 * 60)
        #expect(timer.remaining(at: t0 + 61 * 60) == 19 * 60)
    }

    @Test func toggleAlternatesBetweenRunningAndPaused() {
        var timer = FocusTimer(plan: plan)
        timer.toggle(at: t0)
        #expect(timer.isRunning)
        timer.toggle(at: t0 + 1)
        #expect(timer.isPaused)
        timer.toggle(at: t0 + 2)
        #expect(timer.isRunning)
    }

    @Test func pausingAnIdleTimerDoesNothing() {
        var timer = FocusTimer(plan: plan)
        timer.pause(at: t0)
        #expect(timer.isIdle)
        timer.start(at: t0)
        timer.start(at: t0 + 60)
        #expect(timer.remaining(at: t0 + 60) == 24 * 60, "starting a running timer doesn't restart it")
    }

    @Test func tickMovesOnOnlyWhenThePhaseHasRunOut() {
        var timer = FocusTimer(plan: plan)
        timer.start(at: t0)
        #expect(timer.tick(at: t0 + 10 * 60, autoStart: false) == nil)
        #expect(timer.phase == .focus)
        #expect(timer.tick(at: t0 + 25 * 60, autoStart: false) == .focus)
        #expect(timer.phase == .shortBreak)
        #expect(timer.isIdle)
        #expect(timer.completedSessions == 1)
        #expect(timer.sessionNumber == 2, "a break is followed by the second session")
        #expect(timer.remaining(at: t0 + 25 * 60) == 5 * 60)
    }

    @Test func autoStartRunsTheNextPhaseAtOnce() {
        var timer = FocusTimer(plan: plan)
        timer.start(at: t0)
        let end = t0 + 25 * 60
        #expect(timer.tick(at: end, autoStart: true) == .focus)
        #expect(timer.isRunning)
        #expect(timer.remaining(at: end + 60) == 4 * 60)
        #expect(timer.tick(at: end + 5 * 60, autoStart: true) == .shortBreak)
        #expect(timer.phase == .focus)
        #expect(timer.isRunning)
    }

    @Test func everyFourthSessionEarnsALongBreak() {
        var timer = FocusTimer(plan: plan)
        var now = t0
        for session in 1 ... 4 {
            #expect(timer.phase == .focus)
            #expect(timer.sessionNumber == session)
            timer.skip(at: now, autoStart: false)
            now += 1
            #expect(timer.phase == (session == 4 ? .longBreak : .shortBreak))
            timer.skip(at: now, autoStart: false)
            now += 1
        }
        #expect(timer.completedSessions == 4)
        #expect(timer.sessionNumber == 1, "the cycle starts over")
        #expect(timer.phase == .focus)
    }

    @Test func skipReturnsThePhaseThatEnded() {
        var timer = FocusTimer(plan: plan)
        #expect(timer.skip(at: t0, autoStart: false) == .focus)
        #expect(timer.skip(at: t0, autoStart: false) == .shortBreak)
        #expect(timer.completedSessions == 1, "skipping a break doesn't count as a session")
    }

    @Test func resetReturnsToTheStartOfThePhase() {
        var timer = FocusTimer(plan: plan)
        timer.skip(at: t0, autoStart: true)
        timer.reset()
        #expect(timer.isIdle)
        #expect(timer.phase == .shortBreak)
        #expect(timer.completedSessions == 1)
        timer.resetCycle()
        #expect(timer.phase == .focus)
        #expect(timer.completedSessions == 0)
        #expect(timer.isIdle)
    }

    @Test func aNewPlanAppliesToPhasesThatHaveNotStarted() {
        var timer = FocusTimer(plan: plan)
        timer.setPlan(FocusTimer.Plan(focus: 50 * 60))
        #expect(timer.remaining(at: t0) == 50 * 60)
        timer.start(at: t0)
        timer.setPlan(FocusTimer.Plan(focus: 10 * 60))
        #expect(timer.remaining(at: t0 + 60) == 49 * 60, "a running phase keeps its length")
        #expect(timer.duration == 10 * 60)
    }

    @Test func planDurationsAreNeverZero() {
        let plan = FocusTimer.Plan(focus: 0, shortBreak: -5, longBreak: 0, sessionsBeforeLongBreak: 0)
        #expect(plan.focus == 1)
        #expect(plan.shortBreak == 1)
        #expect(plan.longBreak == 1)
        #expect(plan.sessionsBeforeLongBreak == 1)
        var timer = FocusTimer(plan: plan)
        timer.skip(at: t0, autoStart: false)
        #expect(timer.phase == .longBreak, "with one session per cycle every break is long")
    }

    @Test func phaseTitles() {
        #expect(FocusTimer.Phase.focus.title == "Focus")
        #expect(FocusTimer.Phase.shortBreak.title == "Break")
        #expect(FocusTimer.Phase.longBreak.title == "Long break")
        #expect(!FocusTimer.Phase.focus.isBreak)
        #expect(FocusTimer.Phase.longBreak.isBreak)
    }
}
