import DockCore
import Foundation
import Testing

@testable import SystemServices

private func appTile(_ url: String, type: Int = 15) -> [String: Any] {
    [
        "tile-type": "file-tile",
        "tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": type]],
    ]
}

@Suite("Apple's Dock apps")
struct AppleDockAppsTests {
    @Test func readsAppURLsInDockOrder() {
        let urls = AppleDockApps.appURLs(fromPersistentApps: [
            appTile("file:///System/Applications/Mail.app/"),
            appTile("file:///Applications/Visual%20Studio%20Code.app/"),
            appTile("/Applications/Safari.app", type: 0),
        ])
        #expect(
            urls.map(\.normalizedPath) == [
                "/System/Applications/Mail.app",
                "/Applications/Visual Studio Code.app",
                "/Applications/Safari.app",
            ])
    }

    @Test func skipsSpacersAndNonApps() {
        let urls = AppleDockApps.appURLs(fromPersistentApps: [
            ["tile-type": "spacer-tile", "tile-data": [String: Any]()],
            ["tile-type": "small-spacer-tile"],
            appTile("file:///Users/me/Downloads/"),
            appTile("https://example.com/App.app"),
            ["tile-data": ["file-data": [String: Any]()]],
            appTile("file:///Applications/Notes.app/"),
        ])
        #expect(urls.map(\.normalizedPath) == ["/Applications/Notes.app"])
    }
}
