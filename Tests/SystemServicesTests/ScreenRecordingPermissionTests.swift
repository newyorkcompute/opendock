import Foundation
import Testing

@testable import SystemServices

/// The Screen Recording switch in System Settings, with no system prompt behind it.
@MainActor
final class FakeScreenRecordingBackend: ScreenRecordingPermissionBackend {
    var isGranted: Bool
    var prompts = 0
    var settingsOpened = 0
    /// What the user answers when prompted.
    var grantsOnPrompt = false

    init(granted: Bool = false) {
        isGranted = granted
    }

    func prompt() {
        prompts += 1
        if grantsOnPrompt { isGranted = true }
    }

    func openSystemSettings() { settingsOpened += 1 }
}

@MainActor
@Suite("Screen Recording permission")
struct ScreenRecordingPermissionTests {
    @Test func startsFromTheSystemsAnswerWithoutPrompting() {
        let backend = FakeScreenRecordingBackend(granted: true)
        let permission = ScreenRecordingPermission(backend: backend)
        #expect(permission.isGranted)
        #expect(backend.prompts == 0)
    }

    @Test func checkingAgainDoesNotPrompt() {
        let backend = FakeScreenRecordingBackend()
        let permission = ScreenRecordingPermission(backend: backend)
        #expect(!permission.refresh())
        backend.isGranted = true
        #expect(permission.refresh())
        #expect(backend.prompts == 0)
        #expect(backend.settingsOpened == 0)
    }

    @Test func promptsOnceThenOpensSystemSettings() {
        let backend = FakeScreenRecordingBackend()
        let permission = ScreenRecordingPermission(backend: backend)
        permission.request()
        permission.request()
        #expect(backend.prompts == 1)
        #expect(backend.settingsOpened == 1)
        #expect(!permission.isGranted)
    }

    @Test func noticesAGrantMadeAtThePrompt() {
        let backend = FakeScreenRecordingBackend()
        backend.grantsOnPrompt = true
        let permission = ScreenRecordingPermission(backend: backend)
        permission.request()
        #expect(permission.isGranted)
        permission.request()
        #expect(backend.prompts == 1)
        #expect(backend.settingsOpened == 0)
    }

    @Test func doesNotAskOnceAllowed() {
        let backend = FakeScreenRecordingBackend()
        let permission = ScreenRecordingPermission(backend: backend)
        backend.isGranted = true
        permission.request()
        #expect(backend.prompts == 0)
        #expect(backend.settingsOpened == 0)
        #expect(permission.isGranted)
    }
}
