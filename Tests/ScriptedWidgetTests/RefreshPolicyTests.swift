import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted refresh policy")
struct RefreshPolicyTests {
    @Test func clampsIntoTheHostRange() {
        #expect(ScriptedRefreshPolicy.interval(requested: 30) == 30)
        #expect(ScriptedRefreshPolicy.interval(requested: 0.1) == 1)
        #expect(ScriptedRefreshPolicy.interval(requested: 1) == 1)
        #expect(ScriptedRefreshPolicy.interval(requested: 86400) == 3600)
        #expect(ScriptedRefreshPolicy.interval(requested: 3600) == 3600)
    }

    @Test func noRequestMeansNoRefresh() {
        #expect(ScriptedRefreshPolicy.interval(requested: nil) == nil)
        #expect(ScriptedRefreshPolicy.interval(requested: 0) == nil)
        #expect(ScriptedRefreshPolicy.interval(requested: -5) == nil)
        #expect(ScriptedRefreshPolicy.interval(requested: .nan) == nil)
        #expect(ScriptedRefreshPolicy.interval(requested: .infinity) == nil)
    }

    @Test func honorsTightenedLimits() {
        var limits = ScriptedWidgetLimits()
        limits.refreshRange = 5 ... 60
        #expect(ScriptedRefreshPolicy.interval(requested: 1, limits: limits) == 5)
        #expect(ScriptedRefreshPolicy.interval(requested: 600, limits: limits) == 60)
    }

    @Test func schedulesTheNextRender() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(ScriptedRefreshPolicy.delayUntilNextRender(lastRender: nil, interval: nil, now: now) == 0)
        #expect(ScriptedRefreshPolicy.delayUntilNextRender(lastRender: nil, interval: 10, now: now) == 0)
        #expect(ScriptedRefreshPolicy.delayUntilNextRender(lastRender: now, interval: nil, now: now) == nil)
        #expect(
            ScriptedRefreshPolicy.delayUntilNextRender(lastRender: now.addingTimeInterval(-4), interval: 10, now: now)
                == 6)
        #expect(
            ScriptedRefreshPolicy.delayUntilNextRender(lastRender: now.addingTimeInterval(-40), interval: 10, now: now)
                == 0)
        #expect(ScriptedRefreshPolicy.delayUntilNextRender(lastRender: now, interval: 10, now: now) == 10)
    }

    @Test func defaultLimitsAreSane() {
        let limits = ScriptedWidgetLimits.default
        #expect(limits.renderTimeout < limits.loadTimeout)
        #expect(limits.refreshRange.lowerBound >= 1)
        #expect(limits.maxTileBytes < limits.maxScriptBytes)
        #expect(limits.maxDepth >= 2)
    }
}
