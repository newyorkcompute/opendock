import Foundation
import Testing

@testable import DockCore

private func app(_ bundleID: String?, path: String? = nil) -> AppItem {
    AppItem(url: URL(fileURLWithPath: path ?? "/Applications/\(bundleID ?? "App").app"), bundleIdentifier: bundleID)
}

private func pinned(_ bundleID: String?, path: String? = nil) -> DockItem {
    DockItem(kind: .app(app(bundleID, path: path)))
}

private let mail = app("com.example.mail")
private let notes = app("com.example.notes")
private let music = app("com.example.music")

@Suite("Recent apps")
struct RecentAppsTests {
    @Test func newestComesFirst() {
        var recents = RecentApps()
        let recordedMail = recents.record(mail)
        let recordedNotes = recents.record(notes)
        #expect(recordedMail && recordedNotes)
        #expect(recents.apps == [notes, mail])
    }

    @Test func usingAnAppAgainMovesItToTheFront() {
        var recents = RecentApps([music, notes, mail])
        let changed = recents.record(mail)
        #expect(changed)
        #expect(recents.apps == [mail, music, notes])
    }

    @Test func usingTheMostRecentAppAgainChangesNothing() {
        var recents = RecentApps([notes, mail])
        let changed = recents.record(notes)
        #expect(!changed)
        #expect(recents.apps == [notes, mail])
    }

    @Test func anAppThatMovedIsStillOneApp() {
        var recents = RecentApps([notes, mail])
        let moved = app("com.example.mail", path: "/Users/me/Apps/Mail.app")
        let changed = recents.record(moved)
        #expect(changed)
        #expect(recents.apps == [moved, notes])
    }

    @Test func appsWithoutBundleIdentifiersAreToldApartByPath() {
        var recents = RecentApps()
        recents.record(app(nil, path: "/Applications/A.app"))
        recents.record(app(nil, path: "/Applications/B.app"))
        recents.record(app(nil, path: "/Applications/A.app/"))
        #expect(recents.apps.map(\.url.normalizedPath) == ["/Applications/A.app", "/Applications/B.app"])
    }

    @Test func remembersNoMoreThanTheCapacity() {
        var recents = RecentApps()
        for n in 0 ..< RecentApps.capacity + 5 {
            recents.record(app("com.example.app\(n)"))
        }
        #expect(recents.apps.count == RecentApps.capacity)
        #expect(recents.apps.first?.bundleIdentifier == "com.example.app\(RecentApps.capacity + 4)")
        #expect(recents.apps.last?.bundleIdentifier == "com.example.app5")
    }

    @Test func forgetsAppsThatNoLongerExistWhenRecording() {
        var recents = RecentApps([music, notes])
        recents.record(mail) { $0.normalizedPath != notes.url.normalizedPath }
        #expect(recents.apps == [mail, music])
    }

    @Test func initDropsDuplicatesKeepingTheNewest() {
        let recents = RecentApps([mail, notes, app("com.example.mail", path: "/Old/Mail.app"), music])
        #expect(recents.apps == [mail, notes, music])
    }

    @Test func removeForgetsAnApp() {
        var recents = RecentApps([notes, mail])
        let removed = recents.remove(app("com.example.mail", path: "/Elsewhere/Mail.app"))
        #expect(removed)
        #expect(recents.apps == [notes])
        let removedAgain = recents.remove(mail)
        #expect(!removedAgain)
    }

    // MARK: Shown

    private func shown(
        _ recents: RecentApps,
        pinned: [DockItem] = [],
        runningIDs: Set<String> = [],
        runningPaths: Set<String> = [],
        own: String? = nil,
        limit: Int = 3
    ) -> [String] {
        recents.shown(
            pinned: pinned, runningBundleIDs: runningIDs, runningBundlePaths: runningPaths, excludingBundleID: own,
            limit: limit
        ).map(\.app.displayName)
    }

    @Test func showsTheNewestFirstUpToTheLimit() {
        let recents = RecentApps([music, notes, mail, app("com.example.safari")])
        #expect(shown(recents, limit: 3) == ["com.example.music", "com.example.notes", "com.example.mail"])
        #expect(shown(recents, limit: 1) == ["com.example.music"])
        #expect(shown(recents, limit: 0).isEmpty)
    }

    @Test func hidesPinnedAppsByBundleIdentifierOrPath() {
        let recents = RecentApps([music, notes, mail])
        let items = [
            pinned("com.example.notes", path: "/Somewhere/Else/Notes.app"),
            pinned(nil, path: "/Applications/com.example.mail.app/"),
        ]
        #expect(shown(recents, pinned: items) == ["com.example.music"])
    }

    @Test func hidesRunningAppsByBundleIdentifierOrPath() {
        let recents = RecentApps([music, notes, mail])
        #expect(shown(recents, runningIDs: ["com.example.notes"]) == ["com.example.music", "com.example.mail"])
        #expect(
            shown(recents, runningPaths: ["/Applications/com.example.music.app"]) == [
                "com.example.notes", "com.example.mail",
            ])
    }

    @Test func hiddenAppsDoNotCountTowardTheLimit() {
        let recents = RecentApps([music, notes, mail])
        #expect(
            shown(recents, runningIDs: ["com.example.music"], limit: 2) == ["com.example.notes", "com.example.mail"])
    }

    @Test func hidesItselfButKeepsAppsWithoutBundleIdentifier() {
        let unbundled = app(nil, path: "/Applications/Unbundled.app")
        let recents = RecentApps([app("com.newyorkcompute.opendock"), unbundled, mail])
        #expect(shown(recents, own: "com.newyorkcompute.opendock") == ["Unbundled", "com.example.mail"])
        // Run unbundled, OpenDock has no bundle identifier; that must not hide other apps without one.
        #expect(shown(recents, own: nil) == ["com.newyorkcompute.opendock", "Unbundled", "com.example.mail"])
    }

    @Test func identityIsTheBundlePath() {
        let a = RecentDockApp(app: app("com.example.mail", path: "/Applications/Mail.app/"))
        let b = RecentDockApp(app: app(nil, path: "/Applications/Mail.app"))
        #expect(a.id == b.id)
        #expect(a.id != RecentDockApp(app: notes).id)
    }

    @Test func roundTripsAsAListOfApps() throws {
        let recents = RecentApps([notes, mail])
        let data = try JSONEncoder().encode(recents)
        #expect(try JSONDecoder().decode([AppItem].self, from: data) == [notes, mail])
        #expect(try JSONDecoder().decode(RecentApps.self, from: data) == recents)
    }
}
