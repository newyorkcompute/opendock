import Foundation
import Testing

@testable import SystemServices

@Suite("Widget notifier")
struct WidgetNotifierTests {
    @Test func notificationsNeedAnAppBundleWithAnIdentifier() {
        let app = URL(fileURLWithPath: "/Applications/OpenDock.app")
        #expect(WidgetNotifier.canNotify(bundleURL: app, bundleIdentifier: "com.newyorkcompute.opendock"))
        #expect(!WidgetNotifier.canNotify(bundleURL: app, bundleIdentifier: nil))
        let bareBinary = URL(fileURLWithPath: "/Users/me/opendock/.build/debug")
        #expect(!WidgetNotifier.canNotify(bundleURL: bareBinary, bundleIdentifier: "com.newyorkcompute.opendock"))
        let testBundle = URL(fileURLWithPath: "/tmp/OpenDockPackageTests.xctest")
        #expect(!WidgetNotifier.canNotify(bundleURL: testBundle, bundleIdentifier: "com.apple.dt.xctest.tool"))
    }

    @Test func theTestProcessIsNotAnApp() {
        // `WidgetNotifier.shared` must be safe to touch from tests; this is what keeps it so.
        #expect(!WidgetNotifier.isAvailable)
    }
}
