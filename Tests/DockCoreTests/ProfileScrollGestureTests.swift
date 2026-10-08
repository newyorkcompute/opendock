import Foundation
import Testing
@testable import DockCore

@Suite("Profile scroll gesture")
struct ProfileScrollGestureTests {
    private typealias Event = ProfileScrollGesture.Event

    /// Feeds a trackpad gesture as `samples` (dx, dy) pairs and returns every step it produced.
    private func swipe(_ samples: [(Double, Double)], command: Bool = false, gesture: inout ProfileScrollGesture) -> [Int] {
        var steps: [Int] = []
        for (index, sample) in samples.enumerated() {
            let event = Event(
                deltaX: sample.0,
                deltaY: sample.1,
                phase: index == 0 ? .began : .changed,
                isCommandDown: command,
                timestamp: Double(index) * 0.016
            )
            if let step = gesture.handle(event) { steps.append(step) }
        }
        _ = gesture.handle(Event(deltaX: 0, deltaY: 0, phase: .ended, timestamp: 1))
        return steps
    }

    private func swipe(_ samples: [(Double, Double)], command: Bool = false) -> [Int] {
        var gesture = ProfileScrollGesture()
        return swipe(samples, command: command, gesture: &gesture)
    }

    @Test func sidewaysSwipeSwitchesOncePerGesture() {
        #expect(swipe(Array(repeating: (-10, 1), count: 20)) == [1])
        #expect(swipe(Array(repeating: (10, -1), count: 20)) == [-1])
    }

    @Test func shortSwipesDoNothing() {
        #expect(swipe([(-10, 0), (-10, 0), (-10, 0)]).isEmpty)
    }

    @Test func eachGestureCountsFromZero() {
        var gesture = ProfileScrollGesture()
        #expect(swipe([(-20, 0), (-10, 0)], gesture: &gesture).isEmpty)
        #expect(swipe([(-20, 0), (-10, 0)], gesture: &gesture).isEmpty)
        #expect(swipe([(-20, 0), (-20, 0)], gesture: &gesture) == [1])
        #expect(swipe([(20, 0), (20, 0)], gesture: &gesture) == [-1])
    }

    @Test func verticalScrollingNeedsCommand() {
        #expect(swipe(Array(repeating: (2, -10), count: 10)).isEmpty)
        #expect(swipe(Array(repeating: (2, -10), count: 10), command: true) == [1])
        #expect(swipe(Array(repeating: (0, 10), count: 10), command: true) == [-1])
    }

    @Test func diagonalSwipesWithoutCommandDoNothing() {
        #expect(swipe(Array(repeating: (-10, -8), count: 10)).isEmpty)
    }

    @Test func momentumIsIgnored() {
        var gesture = ProfileScrollGesture()
        for index in 0 ..< 30 {
            let event = Event(deltaX: -20, deltaY: 0, phase: .none, isMomentum: true, timestamp: Double(index))
            #expect(gesture.handle(event) == nil)
        }
    }

    @Test func mouseWheelWithCommandStepsAtMostOncePerInterval() {
        var gesture = ProfileScrollGesture()
        func notch(_ dy: Double, at time: TimeInterval, command: Bool = true) -> Int? {
            gesture.handle(Event(deltaX: 0, deltaY: dy, phase: .none, isCommandDown: command, timestamp: time))
        }
        #expect(notch(-1, at: 10) == 1)
        #expect(notch(-1, at: 10.1) == nil)
        #expect(notch(-1, at: 10.1 + ProfileScrollGesture.wheelInterval) == 1)
        #expect(notch(1, at: 11) == -1)
        #expect(notch(1, at: 12, command: false) == nil)
    }

    @Test func horizontalWheelSwitchesWithoutCommand() {
        var gesture = ProfileScrollGesture()
        #expect(gesture.handle(Event(deltaX: -1, deltaY: 0, phase: .none, timestamp: 0)) == 1)
        #expect(gesture.handle(Event(deltaX: 1, deltaY: 0, phase: .none, timestamp: 1)) == -1)
    }
}
