import Foundation
import Testing

@testable import DockCore

@Suite("Removing an item by dragging it off the dock")
struct DragOffRemovalTests {
    private let hold = DragOffRemoval.holdDuration
    private let threshold = 100.0

    private func moved(_ removal: inout DragOffRemoval, to distance: Double, at now: TimeInterval)
        -> DragOffRemoval.Change
    {
        removal.pointerMoved(distance: distance, threshold: threshold, now: now)
    }

    @Test func startsNearTheDock() {
        let removal = DragOffRemoval()
        #expect(!removal.isClear)
        #expect(!removal.isArmed)
    }

    @Test func nearTheDockNothingHappens() {
        var removal = DragOffRemoval()
        #expect(moved(&removal, to: 0, at: 10) == .none)
        #expect(moved(&removal, to: threshold / 2, at: 11) == .none)
        #expect(moved(&removal, to: threshold, at: 10 + hold * 10) == .none, "the threshold itself isn't clear")
        #expect(!removal.isClear)
        #expect(!removal.isArmed)
    }

    @Test func gettingClearStartsTheHold() {
        var removal = DragOffRemoval()
        #expect(moved(&removal, to: threshold + 1, at: 10) == .none)
        #expect(removal.isClear)
        #expect(removal.clearSince == 10)
        #expect(!removal.isArmed, "not until the hold is over")
    }

    @Test func aQuickOvershootSnapsBack() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 3, at: 10)
        #expect(moved(&removal, to: threshold / 2, at: 10 + hold / 2) == .none)
        #expect(!removal.isClear)
        #expect(!removal.isArmed)
        // Clear again later: the earlier time away doesn't count.
        #expect(moved(&removal, to: threshold * 3, at: 10 + hold) == .none)
        #expect(moved(&removal, to: threshold * 3, at: 10 + hold * 1.5) == .none)
        #expect(moved(&removal, to: threshold * 3, at: 10 + hold * 2) == .armed)
    }

    @Test func stayingClearForTheHoldArms() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 2, at: 10)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold / 2) == .none)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold) == .armed)
        #expect(removal.isArmed)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold * 2) == .none, "armed only once")
        #expect(removal.isArmed)
    }

    @Test func movingWhileClearKeepsTheHoldGoing() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold + 10, at: 10)
        _ = moved(&removal, to: threshold + 50, at: 10.1)
        _ = moved(&removal, to: threshold + 5, at: 10.2)
        #expect(removal.clearSince == 10, "the hold doesn't need the pointer to rest")
        #expect(moved(&removal, to: threshold + 20, at: 10 + hold) == .armed)
    }

    @Test func aRestingPointerArmsOnATick() {
        // The pointer stops moving once it's clear; the caller's timer feeds the same
        // distance again and that completes the hold.
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 2, at: 10)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold - 0.01) == .none)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold + 0.01) == .armed)
    }

    @Test func comingBackDisarms() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 2, at: 10)
        _ = moved(&removal, to: threshold * 2, at: 10 + hold)
        #expect(removal.isArmed)
        #expect(moved(&removal, to: threshold / 2, at: 11) == .disarmed)
        #expect(!removal.isArmed)
        #expect(!removal.isClear)
        #expect(moved(&removal, to: 0, at: 12) == .none, "disarmed only once")
    }

    @Test func armedAgainOnlyAfterAnotherHold() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 2, at: 10)
        _ = moved(&removal, to: threshold * 2, at: 10 + hold)
        _ = moved(&removal, to: 0, at: 11)
        #expect(moved(&removal, to: threshold * 2, at: 12) == .none)
        #expect(moved(&removal, to: threshold * 2, at: 12 + hold / 2) == .none)
        #expect(moved(&removal, to: threshold * 2, at: 12 + hold) == .armed)
    }

    @Test func jitterAtTheThresholdDoesNotFlicker() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold + 1, at: 10)
        _ = moved(&removal, to: threshold + 1, at: 10 + hold)
        #expect(removal.isArmed)
        // A little way back in is still armed; well back in isn't.
        #expect(moved(&removal, to: threshold - 1, at: 11) == .none)
        #expect(removal.isArmed)
        #expect(moved(&removal, to: threshold * DragOffRemoval.disarmFraction + 1, at: 11.1) == .none)
        #expect(removal.isArmed)
        #expect(moved(&removal, to: threshold * DragOffRemoval.disarmFraction - 1, at: 11.2) == .disarmed)
    }

    @Test func beforeArmingTheThresholdIsStrict() {
        // The slack only applies once armed, so a pointer hovering just inside the
        // threshold never arms.
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold - 1, at: 10)
        #expect(!removal.isClear)
        #expect(moved(&removal, to: threshold - 1, at: 10 + hold * 2) == .none)
        #expect(!removal.isArmed)
    }

    @Test func resetForgetsEverything() {
        var removal = DragOffRemoval()
        _ = moved(&removal, to: threshold * 2, at: 10)
        _ = moved(&removal, to: threshold * 2, at: 10 + hold)
        removal.reset()
        #expect(!removal.isArmed)
        #expect(!removal.isClear)
        // Still clear, but a fresh hold has to run.
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold) == .none)
        #expect(moved(&removal, to: threshold * 2, at: 10 + hold * 2) == .armed)
    }

    @Test func holdIsShortLikeApplesDock() {
        #expect(hold >= 0.3 && hold <= 1.0)
    }

    @Test func thresholdGrowsWithTheIconsButHasAFloor() {
        #expect(DragOffRemoval.threshold(iconSize: 64) == DragOffRemoval.minimumThreshold)
        #expect(DragOffRemoval.threshold(iconSize: 32) == DragOffRemoval.minimumThreshold)
        #expect(DragOffRemoval.threshold(iconSize: 128) == 192)
        #expect(DragOffRemoval.threshold(iconSize: 100) == 150)
    }

    @Test func distanceFromTheDockIsZeroInsideIt() {
        let zone = CGRect(x: 100, y: 0, width: 400, height: 80)
        #expect(DragOffRemoval.distance(from: CGPoint(x: 300, y: 40), to: zone) == 0)
        #expect(DragOffRemoval.distance(from: CGPoint(x: 100, y: 0), to: zone) == 0, "the edge counts as inside")
        #expect(DragOffRemoval.distance(from: CGPoint(x: 500, y: 80), to: zone) == 0)
    }

    @Test func distanceFromTheDockIsToItsNearestPoint() {
        let zone = CGRect(x: 100, y: 0, width: 400, height: 80)
        // Straight out from a side, on every side: a dock on any edge works the same.
        #expect(DragOffRemoval.distance(from: CGPoint(x: 300, y: 180), to: zone) == 100)
        #expect(DragOffRemoval.distance(from: CGPoint(x: 300, y: -50), to: zone) == 50)
        #expect(DragOffRemoval.distance(from: CGPoint(x: 40, y: 40), to: zone) == 60)
        #expect(DragOffRemoval.distance(from: CGPoint(x: 530, y: 40), to: zone) == 30)
        // Past a corner it's the diagonal, not the larger of the two.
        #expect(DragOffRemoval.distance(from: CGPoint(x: 530, y: 120), to: zone) == 50)
    }
}

@Suite("The poof")
struct PoofCloudTests {
    private let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

    @Test func everyFrameHasTheSamePuffs() {
        for progress in steps {
            #expect(PoofCloud.puffs(at: progress).count == PoofCloud.puffCount)
            #expect(PoofCloud.puffs(at: progress, reduceMotion: true).count == PoofCloud.puffCount)
        }
        #expect(PoofCloud.puffCount >= 5, "enough puffs to read as a cloud")
    }

    @Test func theCloudStaysInsideItsSquare() {
        for reduceMotion in [false, true] {
            for progress in steps {
                for puff in PoofCloud.puffs(at: progress, reduceMotion: reduceMotion) {
                    #expect(abs(puff.x) + puff.radius <= 1)
                    #expect(abs(puff.y) + puff.radius <= 1)
                    #expect(puff.radius > 0)
                }
            }
        }
    }

    @Test func theCloudBillowsOut() {
        var previous = PoofCloud.puffs(at: 0)
        for progress in steps.dropFirst() {
            let frame = PoofCloud.puffs(at: progress)
            for (before, after) in zip(previous, frame) {
                #expect(hypot(after.x, after.y) >= hypot(before.x, before.y), "puffs drift outward")
                #expect(after.radius >= before.radius, "and grow as they thin")
            }
            previous = frame
        }
        let first = PoofCloud.puffs(at: 0).dropFirst()
        let last = PoofCloud.puffs(at: 1).dropFirst()
        for (before, after) in zip(first, last) {
            #expect(hypot(after.x, after.y) > hypot(before.x, before.y) * 2, "it ends up well spread out")
        }
    }

    @Test func theCloudFadesAway() {
        let opacities = steps.map { PoofCloud.puffs(at: $0)[0].opacity }
        #expect(opacities.first == 0, "it starts from nothing")
        #expect(opacities.last == 0, "and is gone at the end")
        #expect(opacities.max() ?? 0 > 0.95, "but is fully there in between")
        let peak = opacities.firstIndex(of: opacities.max() ?? 0) ?? 0
        #expect(Double(peak) / Double(opacities.count) < 0.25, "it appears at once")
        for (before, after) in zip(opacities[peak...], opacities[peak...].dropFirst()) {
            #expect(after <= before, "then only thins out")
        }
    }

    @Test func allPuffsFadeTogether() {
        for progress in steps {
            let frame = PoofCloud.puffs(at: progress)
            #expect(Set(frame.map(\.opacity)).count == 1)
        }
    }

    @Test func reduceMotionOnlyFades() {
        let first = PoofCloud.puffs(at: 0.2, reduceMotion: true)
        for progress in steps {
            let frame = PoofCloud.puffs(at: progress, reduceMotion: true)
            for (reference, puff) in zip(first, frame) {
                #expect(puff.x == reference.x && puff.y == reference.y, "nothing moves")
                #expect(puff.radius == reference.radius, "nothing grows")
            }
            #expect(frame[0].opacity == PoofCloud.puffs(at: progress)[0].opacity, "the fade is the same")
        }
    }

    @Test func progressIsClamped() {
        #expect(PoofCloud.puffs(at: -1) == PoofCloud.puffs(at: 0))
        #expect(PoofCloud.puffs(at: 2) == PoofCloud.puffs(at: 1))
    }

    @Test func isBrief() {
        #expect(PoofCloud.duration >= 0.25 && PoofCloud.duration <= 0.8)
    }
}
