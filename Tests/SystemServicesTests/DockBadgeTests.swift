import DockCore
import Foundation
import Testing

@testable import SystemServices

/// Stands in for Apple's Dock.
@MainActor
final class FakeDockBadgeSource: DockBadgeSource {
    var badges: [DockBadge] = []
    var error: DockBadgeReadError?
    var reads = 0

    init() {}

    func readBadges() async throws -> [DockBadge] {
        reads += 1
        if let error { throw error }
        return badges
    }
}

private let mail = AppItem(
    url: URL(fileURLWithPath: "/System/Applications/Mail.app"), bundleIdentifier: "com.apple.mail")
private let slack = AppItem(
    url: URL(fileURLWithPath: "/Applications/Slack.app"), bundleIdentifier: "com.tinyspeck.slackmacgap")

@Suite("DockBadge from Apple's Dock tiles")
struct DockBadgeTileTests {
    @Test func readsAnAppTilesLabel() {
        let badge = DockBadge(
            subrole: "AXApplicationDockItem", statusLabel: "3",
            url: URL(fileURLWithPath: "/Applications/Slack.app/"), title: "Slack")
        #expect(badge?.label == "3")
        #expect(badge?.title == "Slack")
        #expect(badge?.bundleURL?.normalizedPath == "/Applications/Slack.app")
    }

    @Test func ignoresTilesWithoutABadge() {
        #expect(DockBadge(subrole: "AXApplicationDockItem", statusLabel: nil, url: nil, title: "Mail") == nil)
        #expect(DockBadge(subrole: "AXApplicationDockItem", statusLabel: "", url: nil, title: "Mail") == nil)
        #expect(DockBadge(subrole: "AXApplicationDockItem", statusLabel: "  ", url: nil, title: "Mail") == nil)
    }

    @Test func ignoresTilesThatArentApps() {
        #expect(DockBadge(subrole: "AXFolderDockItem", statusLabel: "2", url: nil, title: "Downloads") == nil)
        #expect(DockBadge(subrole: nil, statusLabel: "2", url: nil, title: "Mail") == nil)
    }

    @Test func trimsTheLabel() {
        #expect(DockBadge(subrole: "AXApplicationDockItem", statusLabel: " 12\n", url: nil, title: nil)?.label == "12")
        #expect(DockBadge(subrole: "AXApplicationDockItem", statusLabel: "•", url: nil, title: nil)?.label == "•")
    }
}

@Suite("DockBadges lookup")
struct DockBadgesLookupTests {
    @Test func matchesByBundleIdentifier() {
        let badges = DockBadges([
            DockBadge(
                label: "5", bundleURL: URL(fileURLWithPath: "/Applications/Mail.app"),
                bundleIdentifier: "com.apple.mail")
        ])
        #expect(badges.label(for: mail) == "5")
        #expect(badges.label(for: slack) == nil)
    }

    @Test func matchesByBundleLocation() {
        let badges = DockBadges([DockBadge(label: "2", bundleURL: URL(fileURLWithPath: "/Applications/Slack.app/"))])
        #expect(badges.label(for: AppItem(url: URL(fileURLWithPath: "/Applications/Slack.app"))) == "2")
        #expect(badges.label(for: slack) == "2")
        #expect(badges.label(for: mail) == nil)
    }

    @Test func matchesByNameOnlyWithoutALocation() {
        let byName = DockBadges([DockBadge(label: "1", title: "slack")])
        #expect(byName.label(for: slack) == "1")

        let elsewhere = DockBadges([
            DockBadge(label: "1", title: "Slack", bundleURL: URL(fileURLWithPath: "/Users/me/Old/Slack.app"))
        ])
        #expect(elsewhere.label(for: AppItem(url: URL(fileURLWithPath: "/Applications/Slack.app"))) == nil)
    }

    @Test func emptyHasNoLabels() {
        #expect(DockBadges().isEmpty)
        #expect(DockBadges().label(for: mail) == nil)
    }
}

@MainActor
@Suite("DockBadgeMonitor")
struct DockBadgeMonitorTests {
    private let mailBadge = DockBadge(label: "4", bundleIdentifier: "com.apple.mail")

    private func monitor(
        _ source: FakeDockBadgeSource, enabled: Bool = true, access: FakeAccessibilityBackend? = nil
    ) -> DockBadgeMonitor {
        let permission = AccessibilityPermission(backend: access ?? FakeAccessibilityBackend(trusted: true))
        let monitor = DockBadgeMonitor(source: source, permission: permission)
        monitor.isEnabled = enabled
        return monitor
    }

    /// Waits for the monitor's own polling to catch up.
    private func eventually(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 200 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func refreshPublishesTheDocksBadges() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let monitor = monitor(source)
        await monitor.refresh()
        #expect(monitor.label(for: mail) == "4")
        #expect(monitor.label(for: slack) == nil)
    }

    @Test func enablingStartsPolling() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let monitor = monitor(source)
        await eventually { monitor.label(for: mail) != nil }
        #expect(monitor.label(for: mail) == "4")
    }

    @Test func readsNothingWhileDisabled() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let monitor = monitor(source, enabled: false)
        await monitor.refresh()
        #expect(source.reads == 0)
        #expect(monitor.badges.isEmpty)
    }

    @Test func readsNothingWhileTheDockIsHidden() async {
        let source = FakeDockBadgeSource()
        let monitor = monitor(source, enabled: false)
        monitor.isDockVisible = false
        monitor.isEnabled = true
        await monitor.refresh()
        #expect(source.reads == 0)
    }

    @Test func turningOffClearsTheBadges() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let monitor = monitor(source)
        await monitor.refresh()
        monitor.isEnabled = false
        #expect(monitor.badges.isEmpty)
    }

    @Test func withoutAccessNeverPromptsOrReads() async {
        let source = FakeDockBadgeSource()
        let access = FakeAccessibilityBackend(trusted: false)
        let monitor = monitor(source, access: access)
        #expect(!monitor.permission.isGranted)
        let wait = await monitor.refresh()
        #expect(wait == DockBadgeMonitor.accessCheckInterval)
        #expect(source.reads == 0)
        #expect(access.prompts == 0)
    }

    @Test func picksUpAccessGrantedLater() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let access = FakeAccessibilityBackend(trusted: false)
        let monitor = monitor(source, access: access)
        access.isTrusted = true
        await monitor.refresh()
        #expect(monitor.permission.isGranted)
        #expect(monitor.label(for: mail) == "4")
    }

    @Test func readsAsSoonAsAccessIsGrantedElsewhere() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let access = FakeAccessibilityBackend(trusted: false)
        let monitor = monitor(source, access: access)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(source.reads == 0)
        // Granted in System Settings and noticed by, say, the Settings window.
        access.isTrusted = true
        monitor.permission.refresh()
        await eventually { monitor.label(for: mail) != nil }
        #expect(monitor.label(for: mail) == "4")
    }

    @Test func losingAccessClearsTheBadges() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let access = FakeAccessibilityBackend(trusted: true)
        let monitor = monitor(source, access: access)
        await monitor.refresh()
        source.error = .accessDenied
        let wait = await monitor.refresh()
        #expect(!monitor.permission.isGranted)
        #expect(monitor.badges.isEmpty)
        #expect(wait == DockBadgeMonitor.accessCheckInterval)
    }

    @Test func dockNotRunningClearsTheBadgesButKeepsAccess() async {
        let source = FakeDockBadgeSource()
        source.badges = [mailBadge]
        let monitor = monitor(source)
        await monitor.refresh()
        source.error = .dockNotRunning
        let wait = await monitor.refresh()
        #expect(monitor.permission.isGranted)
        #expect(monitor.badges.isEmpty)
        #expect(wait == DockBadgeMonitor.pollInterval)
    }
}
