import DockCore
import Foundation
import Testing

@testable import SystemServices

@Suite("Recent apps section")
struct RecentDockAppTests {
    private func app(_ bundleID: String?, path: String? = nil) -> AppItem {
        AppItem(
            url: URL(fileURLWithPath: path ?? "/Applications/\(bundleID ?? "App").app"), bundleIdentifier: bundleID)
    }

    @Test func hidesWhatTheRunningSectionShows() {
        var running = RunningAppsMonitor.Snapshot()
        running.runningBundleIDs = ["com.example.notes"]
        running.runningBundlePaths = ["/Applications/Tool.app"]
        let recents = RecentApps([
            app("com.example.notes", path: "/Somewhere/Notes.app"),
            app(nil, path: "/Applications/Tool.app/"),
            app("com.example.mail"),
            app("com.newyorkcompute.opendock"),
        ])
        let pinnedMail = DockItem(kind: .app(app("com.example.mail", path: "/Elsewhere/Mail.app")))

        let all = running.recentApps(from: recents, pinned: [], excludingBundleID: nil, limit: 10)
        #expect(all.map(\.app.displayName) == ["com.example.mail", "com.newyorkcompute.opendock"])

        let shown = running.recentApps(
            from: recents, pinned: [pinnedMail], excludingBundleID: "com.newyorkcompute.opendock", limit: 10)
        #expect(shown.isEmpty)
    }

    @Test func quittingAnAppMovesItFromRunningToRecent() {
        let mail = app("com.example.mail")
        let recents = RecentApps([mail])
        var running = RunningAppsMonitor.Snapshot()
        running.runningBundleIDs = ["com.example.mail"]
        running.runningBundlePaths = [mail.url.normalizedPath]
        #expect(running.recentApps(from: recents, pinned: [], excludingBundleID: nil, limit: 3).isEmpty)

        running = RunningAppsMonitor.Snapshot()
        let afterQuit = running.recentApps(from: recents, pinned: [], excludingBundleID: nil, limit: 3)
        #expect(afterQuit.map(\.id) == [RecentDockApp(app: mail).id])
    }
}
