import Foundation
import Testing

@testable import SystemServices

/// The Accessibility switch in System Settings, with no System Settings behind it.
@MainActor
final class FakeAccessibilityBackend: AccessibilityPermissionBackend {
    var isTrusted: Bool
    var prompts = 0
    var settingsOpened = 0
    /// What the user answers when prompted.
    var grantsOnPrompt = false

    init(trusted: Bool = false) {
        isTrusted = trusted
    }

    func promptForTrust() {
        prompts += 1
        if grantsOnPrompt { isTrusted = true }
    }

    func openSystemSettings() { settingsOpened += 1 }
}

@MainActor
@Suite("Accessibility permission")
struct AccessibilityPermissionTests {
    @Test func startsFromTheSystemsAnswerWithoutPrompting() {
        let backend = FakeAccessibilityBackend(trusted: true)
        let permission = AccessibilityPermission(backend: backend)
        #expect(permission.isGranted)
        #expect(backend.prompts == 0)
    }

    @Test func promptsOnceThenOpensSystemSettings() {
        let backend = FakeAccessibilityBackend()
        let permission = AccessibilityPermission(backend: backend)
        permission.request()
        permission.request()
        #expect(backend.prompts == 1)
        #expect(backend.settingsOpened == 1)
        #expect(!permission.isGranted)
    }

    @Test func noticesAGrantMadeAtThePrompt() {
        let backend = FakeAccessibilityBackend()
        backend.grantsOnPrompt = true
        let permission = AccessibilityPermission(backend: backend)
        permission.request()
        #expect(permission.isGranted)
        // Nothing more to ask for.
        permission.request()
        #expect(backend.prompts == 1)
        #expect(backend.settingsOpened == 0)
    }

    @Test func doesNotAskOnceAllowed() {
        let backend = FakeAccessibilityBackend()
        let permission = AccessibilityPermission(backend: backend)
        backend.isTrusted = true
        permission.request()
        #expect(backend.prompts == 0)
        #expect(backend.settingsOpened == 0)
        #expect(permission.isGranted)
    }

    @Test func refreshNoticesChangesEitherWay() {
        let backend = FakeAccessibilityBackend()
        let permission = AccessibilityPermission(backend: backend)
        backend.isTrusted = true
        #expect(permission.refresh())
        #expect(permission.isGranted)
        backend.isTrusted = false
        #expect(!permission.refresh())
        #expect(!permission.isGranted)
    }

    @Test func aRefusedCallTakesAccessAwayUntilTheNextCheck() {
        let backend = FakeAccessibilityBackend(trusted: true)
        let permission = AccessibilityPermission(backend: backend)
        permission.noteDenied()
        #expect(!permission.isGranted)
        #expect(permission.refresh())
    }
}
