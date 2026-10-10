import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted update scheduling")
struct UpdatePolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func input(
        hasUpdateHook: Bool = true, hasRendered: Bool = true, settingsChanged: Bool = false,
        appearanceChanged: Bool = false, lastRender: Date? = Date(timeIntervalSinceReferenceDate: 10_000),
        refresh: TimeInterval? = 60, visible: Bool = true
    ) -> ScriptedUpdatePolicy.Input {
        ScriptedUpdatePolicy.Input(
            hasUpdateHook: hasUpdateHook, hasRendered: hasRendered, settingsChanged: settingsChanged,
            appearanceChanged: appearanceChanged, lastRender: lastRender, refresh: refresh, now: now,
            visible: visible)
    }

    @Test func hiddenDockDoesNothing() {
        #expect(ScriptedUpdatePolicy.step(input(visible: false)) == .idle)
    }

    @Test func firstDisplayUpdatesWhenTheScriptDefinesUpdate() {
        let first = ScriptedUpdatePolicy.step(input(hasRendered: false, lastRender: nil, refresh: nil))
        #expect(first == .updateThenRender)
        #expect(
            ScriptedUpdatePolicy.step(input(hasUpdateHook: false, hasRendered: false, lastRender: nil, refresh: nil))
                == .render)
    }

    @Test func settingsChangeUpdatesAgain() {
        #expect(ScriptedUpdatePolicy.step(input(settingsChanged: true)) == .updateThenRender)
        #expect(ScriptedUpdatePolicy.step(input(hasUpdateHook: false, settingsChanged: true)) == .render)
    }

    @Test func appearanceChangeRendersFromTheCache() {
        #expect(ScriptedUpdatePolicy.step(input(appearanceChanged: true)) == .render)
    }

    @Test func refreshElapsedUpdatesOrRenders() {
        let rendered = now.addingTimeInterval(-60)
        #expect(ScriptedUpdatePolicy.step(input(lastRender: rendered, refresh: 60)) == .updateThenRender)
        #expect(ScriptedUpdatePolicy.step(input(lastRender: rendered, refresh: 30)) == .updateThenRender)
        #expect(
            ScriptedUpdatePolicy.step(input(hasUpdateHook: false, lastRender: rendered, refresh: 60)) == .render)
    }

    @Test func waitsOutTheRemainderAndIdlesWithoutARefresh() {
        #expect(ScriptedUpdatePolicy.step(input(lastRender: now.addingTimeInterval(-15), refresh: 60)) == .wait(45))
        #expect(ScriptedUpdatePolicy.step(input(refresh: nil)) == .idle)
        #expect(ScriptedUpdatePolicy.step(input(lastRender: now, refresh: 60)) == .wait(60))
    }
}
