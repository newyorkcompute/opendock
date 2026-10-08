import DockCore
import Foundation
import Testing
@testable import SystemServices

@Suite("App launch tracker")
struct AppLaunchTrackerTests {
    private let safari = AppItem(url: URL(filePath: "/Applications/Safari.app"), bundleIdentifier: "com.apple.Safari")
    private let notes = AppItem(url: URL(filePath: "/System/Applications/Notes.app"), bundleIdentifier: "com.apple.Notes")

    @Test func endsWhenTheLaunchedProcessFinishes() {
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        tracker.launched(safari, processIdentifier: 42)
        #expect(tracker.processIdentifiers == [42])
        let ended = tracker.processEnded(processIdentifier: 42, bundleIdentifier: "com.apple.Safari", bundleURL: safari.url)
        #expect(ended == [safari])
        #expect(tracker.isEmpty)
    }

    @Test func matchesByAppUntilTheProcessIsKnown() {
        // The system can announce the launch before Launch Services' answer arrives.
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        #expect(tracker.processIdentifiers.isEmpty)
        let ended = tracker.processEnded(processIdentifier: 42, bundleIdentifier: "com.apple.Safari", bundleURL: nil)
        #expect(ended == [safari])
        #expect(tracker.isEmpty)

        tracker.launchRequested(safari)
        let endedByPath = tracker.processEnded(processIdentifier: 42, bundleIdentifier: nil, bundleURL: URL(filePath: "/Applications/Safari.app/"))
        #expect(endedByPath == [safari])
    }

    @Test func onceTheProcessIsKnownOtherCopiesDontCount() {
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        tracker.launched(safari, processIdentifier: 42)
        let ended = tracker.processEnded(processIdentifier: 7, bundleIdentifier: "com.apple.Safari", bundleURL: safari.url)
        #expect(ended.isEmpty)
        #expect(!tracker.isEmpty)
    }

    @Test func otherAppsDontEndTheLaunch() {
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        tracker.launchRequested(notes)
        let endedNotes = tracker.processEnded(processIdentifier: 9, bundleIdentifier: "com.apple.Notes", bundleURL: notes.url)
        #expect(endedNotes == [notes])
        let endedOther = tracker.processEnded(processIdentifier: 10, bundleIdentifier: "com.example.other", bundleURL: URL(filePath: "/Applications/Other.app"))
        #expect(endedOther.isEmpty)
        #expect(!tracker.isEmpty)
    }

    @Test func watchesEachAppOnce() {
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        tracker.launchRequested(safari)
        tracker.launched(safari, processIdentifier: 42)
        #expect(tracker.processIdentifiers == [42])
        let ended = tracker.processEnded(processIdentifier: 42, bundleIdentifier: nil, bundleURL: nil)
        #expect(ended == [safari])
    }

    @Test func ignoresAnswersForLaunchesNoLongerWatched() {
        var tracker = AppLaunchTracker()
        tracker.launched(safari, processIdentifier: 42)
        #expect(tracker.isEmpty)
        #expect(tracker.processIdentifiers.isEmpty)
    }

    @Test func stopsWatchingFailedLaunches() {
        var tracker = AppLaunchTracker()
        tracker.launchRequested(safari)
        let wasWatched = tracker.stopWatching(safari)
        #expect(wasWatched)
        let wasStillWatched = tracker.stopWatching(safari)
        #expect(!wasStillWatched)
        #expect(tracker.isEmpty)
    }
}
