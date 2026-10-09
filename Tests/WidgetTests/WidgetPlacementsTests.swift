import DockCore
import DockWidgetKit
import Foundation
import Testing

@MainActor
@Suite("Widget placements")
struct WidgetPlacementsTests {
    private let alarm = BuiltInWidgetID.alarm
    private let clock = BuiltInWidgetID.clock

    private func updater(for item: DockItem) -> WidgetSettingsUpdater {
        WidgetSettingsUpdater(id: item.id) { _ in }
    }

    @Test func groupsTheActiveProfilesWidgetsByTypeInDockOrder() {
        let first = DockItem.widget(alarm, settings: ["enabled": "true"])
        let second = DockItem.widget(alarm)
        let clockItem = DockItem.widget(clock)
        let profile = DockProfile(
            name: "Work", items: [.app(at: URL(fileURLWithPath: "/a.app")), first, clockItem, second])
        let document = DockDocument(profiles: [profile], activeProfileID: profile.id)

        let byType = WidgetPlacements.byType(in: document, mayRequestAccess: true, updater: updater)
        #expect(Set(byType.keys) == [alarm, clock])
        let alarms = byType[alarm]
        #expect(alarms?.active.map(\.id) == [first.id, second.id])
        #expect(alarms?.active.first?.instance.settings["enabled"] == "true")
        #expect(alarms?.active.map(\.updater.id) == [first.id, second.id])
        #expect(alarms?.allIDs == [first.id, second.id])
        #expect(alarms?.mayRequestAccess == true)
        #expect(byType[clock]?.active.map(\.id) == [clockItem.id])
    }

    @Test func otherProfilesContributeIDsButNoActivePlacements() {
        let shown = DockItem.widget(alarm)
        let hidden = DockItem.widget(alarm)
        let onlyElsewhere = DockItem.widget(clock)
        let work = DockProfile(name: "Work", items: [shown])
        let home = DockProfile(name: "Home", items: [hidden, onlyElsewhere])
        let document = DockDocument(profiles: [work, home], activeProfileID: work.id)

        let byType = WidgetPlacements.byType(in: document, mayRequestAccess: false, updater: updater)
        #expect(byType[alarm]?.active.map(\.id) == [shown.id])
        #expect(byType[alarm]?.allIDs == [shown.id, hidden.id])
        #expect(byType[clock]?.active.isEmpty == true, "listed, with no active placement")
        #expect(byType[clock]?.allIDs == [onlyElsewhere.id])
        #expect(byType[alarm]?.mayRequestAccess == false)

        var switched = document
        switched.activateProfile(home.id)
        let afterSwitch = WidgetPlacements.byType(in: switched, mayRequestAccess: false, updater: updater)
        #expect(afterSwitch[alarm]?.active.map(\.id) == [hidden.id])
        #expect(afterSwitch[alarm]?.allIDs == [shown.id, hidden.id], "the same items exist")
    }

    @Test func aDocumentWithoutWidgetsHasNoPlacements() {
        let profile = DockProfile(
            name: "Apps", items: [.app(at: URL(fileURLWithPath: "/a.app")), .divider(), .trash()])
        let document = DockDocument(profiles: [profile], activeProfileID: profile.id)
        #expect(WidgetPlacements.byType(in: document, mayRequestAccess: true, updater: updater).isEmpty)
    }

    @Test func placementsCompareBySettingsIDsAndAccessNotByUpdaterIdentity() {
        let item = DockItem.widget(alarm, settings: ["enabled": "true"])
        let profile = DockProfile(name: "Work", items: [item])
        let document = DockDocument(profiles: [profile], activeProfileID: profile.id)

        let once = WidgetPlacements.byType(in: document, mayRequestAccess: true, updater: updater)
        let again = WidgetPlacements.byType(in: document, mayRequestAccess: true, updater: updater)
        #expect(once == again, "a fresh updater closure for the same item is the same placement")

        let notYet = WidgetPlacements.byType(in: document, mayRequestAccess: false, updater: updater)
        #expect(once != notYet, "the welcome window closing is a change widgets hear about")

        var edited = document
        edited.updateWidgets { $0.settings["enabled"] = "false" }
        let afterEdit = WidgetPlacements.byType(in: edited, mayRequestAccess: true, updater: updater)
        #expect(once != afterEdit)
    }
}
