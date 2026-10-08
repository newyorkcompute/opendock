import DockCore
import Foundation
import Testing
@testable import SystemServices

private typealias App = RunningAppsMonitor.AppDescriptor

private func app(
    _ pid: pid_t,
    _ bundleID: String?,
    path: String? = nil,
    launched: TimeInterval? = nil
) -> App {
    let path = path ?? "/Applications/\(bundleID ?? "App\(pid)").app"
    return App(
        processIdentifier: pid,
        bundleIdentifier: bundleID,
        bundleURL: URL(fileURLWithPath: path),
        localizedName: nil,
        launchDate: launched.map(Date.init(timeIntervalSinceReferenceDate:))
    )
}

private func snapshot(_ apps: [App]) -> RunningAppsMonitor.Snapshot {
    var snapshot = RunningAppsMonitor.Snapshot()
    snapshot.regularApps = apps.sorted(by: App.launchedBefore)
    return snapshot
}

private func pinned(_ bundleID: String?, path: String) -> DockItem {
    DockItem(kind: .app(AppItem(url: URL(fileURLWithPath: path), bundleIdentifier: bundleID)))
}

@Suite("Running apps section")
struct RunningDockAppTests {
    @Test func skipsAppsPinnedByBundleIdentifierEvenIfMoved() {
        let running = snapshot([app(10, "com.example.mail", path: "/Users/me/Apps/Mail.app")])
        let items = [pinned("com.example.mail", path: "/Applications/Mail.app")]
        #expect(running.unpinnedApps(pinned: items, excludingBundleID: nil).isEmpty)
    }

    @Test func skipsAppsPinnedByPath() {
        let running = snapshot([app(10, nil, path: "/Applications/Tool.app")])
        let items = [pinned(nil, path: "/Applications/Tool.app/")]
        #expect(running.unpinnedApps(pinned: items, excludingBundleID: nil).isEmpty)
    }

    @Test func ignoresPinnedFoldersAndWidgets() {
        let running = snapshot([app(10, "com.example.notes")])
        let items: [DockItem] = [
            .folder(at: URL(fileURLWithPath: "/Applications/com.example.notes.app")),
            .widget("com.newyorkcompute.opendock.widget.clock"),
            .divider(),
        ]
        #expect(running.unpinnedApps(pinned: items, excludingBundleID: nil).map(\.app.bundleIdentifier) == ["com.example.notes"])
    }

    @Test func skipsItselfButKeepsAppsWithoutBundleIdentifier() {
        let running = snapshot([
            app(10, "com.newyorkcompute.opendock", launched: 1),
            app(11, nil, path: "/Applications/Unbundled.app", launched: 2),
        ])
        let own = running.unpinnedApps(pinned: [], excludingBundleID: "com.newyorkcompute.opendock")
        #expect(own.map(\.id.processIdentifier) == [11])
        // Run unbundled, OpenDock has no bundle identifier; that must not hide other apps without one.
        let unbundled = running.unpinnedApps(pinned: [], excludingBundleID: nil)
        #expect(unbundled.map(\.id.processIdentifier) == [10, 11])
    }

    @Test func skipsAppsWithoutBundleURL() {
        var running = RunningAppsMonitor.Snapshot()
        running.regularApps = [App(processIdentifier: 10, bundleIdentifier: "com.example.x", bundleURL: nil, localizedName: nil, launchDate: nil)]
        #expect(running.unpinnedApps(pinned: [], excludingBundleID: nil).isEmpty)
    }

    @Test func identityIsStableAcrossSnapshots() {
        let mail = app(10, "com.example.mail", launched: 1)
        let notes = app(20, "com.example.notes", launched: 2)
        let before = snapshot([notes, mail]).unpinnedApps(pinned: [], excludingBundleID: nil)

        var after = snapshot([app(30, "com.example.music", launched: 3), notes, mail])
        after.frontmostBundleID = "com.example.notes"
        let next = after.unpinnedApps(pinned: [], excludingBundleID: nil)

        #expect(Array(next.prefix(2)).map(\.id) == before.map(\.id))
        #expect(Set(next.map(\.id)).count == 3)
    }

    @Test func aReusedPidIsANewApp() {
        let first = snapshot([app(10, "com.example.mail", launched: 1)]).unpinnedApps(pinned: [], excludingBundleID: nil)
        let second = snapshot([app(10, "com.example.notes", launched: 50)]).unpinnedApps(pinned: [], excludingBundleID: nil)
        #expect(first[0].id != second[0].id)
    }

    @Test func instancesOfTheSameAppAreSeparate() {
        let running = snapshot([
            app(10, "com.example.term", launched: 1),
            app(11, "com.example.term", launched: 2),
        ])
        let apps = running.unpinnedApps(pinned: [], excludingBundleID: nil)
        #expect(apps.count == 2)
        #expect(apps[0].id != apps[1].id)
    }

    @Test func unpinningReturnsAnAppToItsLaunchPositionWithTheSameIdentity() {
        let running = snapshot([
            app(10, "com.example.mail", launched: 1),
            app(20, "com.example.notes", launched: 2),
            app(30, "com.example.music", launched: 3),
        ])
        let all = running.unpinnedApps(pinned: [], excludingBundleID: nil)
        let whilePinned = running.unpinnedApps(pinned: [pinned("com.example.notes", path: "/x/Notes.app")], excludingBundleID: nil)
        #expect(whilePinned.map(\.id) == [all[0].id, all[2].id])
        #expect(running.unpinnedApps(pinned: [], excludingBundleID: nil) == all)
    }

    @Test func launchOrderIsByLaunchDateThenPid() {
        let apps = [
            app(5, "c", launched: 30),
            app(9, "undated-b"),
            app(7, "a", launched: 10),
            app(3, "undated-a"),
            app(8, "b2", launched: 20),
            app(2, "b1", launched: 20),
        ]
        let order = apps.sorted(by: App.launchedBefore).map(\.processIdentifier)
        #expect(order == [7, 2, 8, 5, 3, 9])
    }

    @Test func launchOrderDoesNotDependOnInputOrder() {
        let apps = (1...8).map { app(pid_t($0), "app\($0)", launched: $0.isMultiple(of: 3) ? nil : Double(9 - $0)) }
        let expected = apps.sorted(by: App.launchedBefore)
        #expect(apps.reversed().sorted(by: App.launchedBefore) == expected)
        #expect(apps.shuffled().sorted(by: App.launchedBefore) == expected)
    }
}
