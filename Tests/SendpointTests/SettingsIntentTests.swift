import Carbon.HIToolbox
import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class SettingsIntentTests: XCTestCase {
    func testTemplateEditorEventsUpdateOnlyTheirField() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let editor = TemplateEditorState(settings: TemplateSettings(defaults: defaults))
        XCTAssertFalse(editor.isDirty)

        var expected = Template.plain
        editor.send(.editName("Work"))
        expected.name = "Work"
        XCTAssertEqual(editor.draft, expected)
        XCTAssertTrue(editor.isDirty)

        editor.send(.editPreamble("Do things"))
        expected.preamble = "Do things"
        XCTAssertEqual(editor.draft, expected)

        editor.send(.editIncludeNoteNumbers(true))
        expected.includeNoteNumbers = true
        XCTAssertEqual(editor.draft, expected)

        editor.send(.editIncludeTimestamps(true))
        expected.includeTimestamps = true
        XCTAssertEqual(editor.draft, expected)

        editor.send(.editIncludeHeading(true))
        expected.includeHeading = true
        XCTAssertEqual(editor.draft, expected)

        editor.send(.editClearStackAfterExport(true))
        expected.clearStackAfterExport = true
        XCTAssertEqual(editor.draft, expected)
        XCTAssertTrue(editor.isDirty)
    }

    func testTemplateEditorEventsDriveIsDirtyRoundTrip() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let editor = TemplateEditorState(settings: settings)

        editor.send(.editPreamble("Changed"))
        XCTAssertTrue(editor.isDirty)
        editor.revert()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .plain)

        editor.send(.editIncludeHeading(true))
        try editor.save()
        XCTAssertFalse(editor.isDirty)
        XCTAssertTrue(settings.activeTemplate.includeHeading)
    }

    func testAppSettingsEventsPersistAcrossInstances() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: {},
            unregisterLoginItem: {}
        )

        settings.send(.exportMode(.copy))
        XCTAssertFalse(settings.pasteDirectly)
        settings.send(.exportMode(.paste))
        XCTAssertTrue(settings.pasteDirectly)

        settings.send(.restoreFocusAfterSave(false))
        XCTAssertFalse(settings.restoreFocusAfterSave)

        settings.send(.launchAtLogin(true))
        XCTAssertTrue(settings.launchAtLogin)

        let reloaded = AppSettings(
            defaults: defaults,
            registerLoginItem: {},
            unregisterLoginItem: {}
        )
        XCTAssertTrue(reloaded.pasteDirectly)
        XCTAssertFalse(reloaded.restoreFocusAfterSave)
    }

    func testAppSettingsFailedLoginItemChangeRollsBack() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        struct Failure: Error {}
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: { throw Failure() },
            unregisterLoginItem: {}
        )
        settings.send(.launchAtLogin(false))
        XCTAssertFalse(settings.launchAtLogin)

        settings.send(.launchAtLogin(true))
        XCTAssertFalse(settings.launchAtLogin, "a failed registration rolls the toggle back")
    }

    func testVoiceSettingsEventsPersistAndClamp() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let voice = VoiceSettings(defaults: defaults)

        voice.send(.voiceMode(.tap))
        XCTAssertEqual(voice.voiceMode, .tap)

        voice.send(.transcriptionPreview(false))
        XCTAssertFalse(voice.transcriptionPreview)

        voice.send(.transcriptionPreviewLines(9))
        XCTAssertEqual(voice.transcriptionPreviewLines, VoiceSettings.previewLinesMax)
        voice.send(.transcriptionPreviewFontSize(3))
        XCTAssertEqual(voice.transcriptionPreviewFontSize, VoiceSettings.previewFontSizeMin)
        voice.send(.transcriptionPreviewOpacity(54))
        XCTAssertEqual(voice.transcriptionPreviewOpacity, 50)

        voice.send(.inputDevice(uid: "mic-1", name: "Mic"))
        XCTAssertEqual(voice.inputDeviceUID, "mic-1")
        XCTAssertEqual(voice.inputDeviceName, "Mic")
        voice.send(.inputDevice(uid: nil, name: "Mic"))
        XCTAssertNil(voice.inputDeviceUID)
        XCTAssertNil(voice.inputDeviceName, "clearing the UID clears the stored name")

        let reloaded = VoiceSettings(defaults: defaults)
        XCTAssertEqual(reloaded.voiceMode, .tap)
        XCTAssertFalse(reloaded.transcriptionPreview)
        XCTAssertEqual(reloaded.transcriptionPreviewLines, VoiceSettings.previewLinesMax)
        XCTAssertEqual(reloaded.transcriptionPreviewFontSize, VoiceSettings.previewFontSizeMin)
        XCTAssertEqual(reloaded.transcriptionPreviewOpacity, 50)
        XCTAssertNil(reloaded.inputDeviceUID)
    }

    func testShortcutIntentPreservesBindingsAndFeedbackText() {
        let (defaults, suite) = makeCenterDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        let center = HotKeyCenter(
            registerEvent: { _, _, _ in (noErr, EventHotKeyRef(bitPattern: 1)) },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        _ = registrar.register(makeActions())

        let previousVoiceCombo = settings.voiceCaptureCombo
        let message = registrar.updateShortcut(settings.captureCombo, for: .voiceCapture)
        XCTAssertEqual(message, ShortcutConflict.duplicate(.capture).localizedDescription)
        XCTAssertEqual(message, "That shortcut is already used by Typed note.")
        XCTAssertEqual(
            settings.voiceCaptureCombo, previousVoiceCombo,
            "a failed rebind leaves the old keys"
        )

        let replacement = KeyCombo(
            keyCode: UInt16(kVK_ANSI_RightBracket),
            modifiers: [.control, .option]
        )
        XCTAssertNil(registrar.updateShortcut(replacement, for: .selectStack(2)))
        XCTAssertEqual(settings.selectStackCombo(2), replacement)

        XCTAssertNil(registrar.updateShortcut(nil, for: .dictate))
        XCTAssertNil(settings.dictateCombo)
    }

    func testStackSettingsIntentSwitchesAndIgnoresTheCurrentStack() async throws {
        let store = try await StackStore(
            persistence: StorePersistence(load: { nil }, commit: { _ in })
        )
        let first = store.stacks[0]
        let second = store.stacks[1]

        StackSettingsIntent.switchTo(stackID: second.id).send(to: store)
        await store.waitForIdle()
        XCTAssertEqual(store.currentStackID, second.id)

        StackSettingsIntent.switchTo(stackID: first.id).send(to: store)
        await store.waitForIdle()
        XCTAssertEqual(store.currentStackID, first.id)

        StackSettingsIntent.switchTo(stackID: first.id).send(to: store)
        XCTAssertFalse(store.hasPendingMutations, "switching to the current stack enqueues nothing")
    }

    // MARK: - Helpers

    private func makeActions() -> HotKeyRegistrar.Actions {
        HotKeyRegistrar.Actions(
            voicePressed: {},
            voiceReleased: {},
            typedNote: {},
            dictatePressed: {},
            dictateReleased: {},
            copy: {},
            showStack: {},
            selectStack: { _ in },
            clear: {}
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsIntentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(suite, forKey: "testSuiteName")
        return defaults
    }

    private func makeCenterDefaults() -> (UserDefaults, String) {
        let suite = "SettingsIntentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func remove(_ defaults: UserDefaults) {
        guard let suite = defaults.string(forKey: "testSuiteName") else { return }
        defaults.removePersistentDomain(forName: suite)
    }
}
