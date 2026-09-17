import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class VoiceShortcutSettingsTests: XCTestCase {
    func testVoiceShortcutAndModeAreAssignableAndPersistAcrossLaunches() throws {
        try withDefaults { defaults in
            let shortcuts = ShortcutSettings(defaults: defaults)
            let voice = VoiceSettings(defaults: defaults)
            let combo = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option, .shift])
            try shortcuts.setShortcut(combo, for: .voiceCapture)
            voice.setVoiceMode(.tap)
            XCTAssertEqual(ShortcutSettings(defaults: defaults).voiceCaptureCombo, combo)
            XCTAssertEqual(VoiceSettings(defaults: defaults).voiceMode, .tap)
            voice.setVoiceMode(.hold)
            XCTAssertEqual(VoiceSettings(defaults: defaults).voiceMode, .hold)

            XCTAssertTrue(voice.transcriptionPreview)
            XCTAssertEqual(voice.transcriptionPreviewLines, 4)
            XCTAssertEqual(voice.transcriptionPreviewFontSize, 13)
            XCTAssertEqual(voice.transcriptionPreviewOpacity, 80)
            voice.setTranscriptionPreview(false)
            voice.setTranscriptionPreviewLines(2)
            voice.setTranscriptionPreviewFontSize(15)
            voice.setTranscriptionPreviewOpacity(70)
            XCTAssertFalse(VoiceSettings(defaults: defaults).transcriptionPreview)
            XCTAssertEqual(VoiceSettings(defaults: defaults).transcriptionPreviewLines, 2)
            XCTAssertEqual(VoiceSettings(defaults: defaults).transcriptionPreviewFontSize, 15)
            XCTAssertEqual(VoiceSettings(defaults: defaults).transcriptionPreviewOpacity, 70)
            voice.setTranscriptionPreviewLines(9)
            voice.setTranscriptionPreviewFontSize(3)
            voice.setTranscriptionPreviewOpacity(54)
            XCTAssertEqual(voice.transcriptionPreviewLines, 5)
            XCTAssertEqual(voice.transcriptionPreviewFontSize, 11)
            XCTAssertEqual(voice.transcriptionPreviewOpacity, 50)
        }
    }

    func testDictationIsOnByDefaultAndStaysOffOnceCleared() throws {
        try withDefaults { defaults in
            let shortcuts = ShortcutSettings(defaults: defaults)
            XCTAssertEqual(shortcuts.dictateCombo, KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option]))
            XCTAssertEqual(
                shortcuts.shortcutConflict(for: KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option]),
                                           excluding: .voiceCapture),
                .duplicate(.dictate)
            )

            shortcuts.clearShortcut(for: .dictate)
            XCTAssertNil(shortcuts.dictateCombo)
            XCTAssertNil(ShortcutSettings(defaults: defaults).dictateCombo, "unbound survives a relaunch")

            let rebound = KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.option])
            try shortcuts.setShortcut(rebound, for: .dictate)
            XCTAssertEqual(ShortcutSettings(defaults: defaults).dictateCombo, rebound)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointVoiceShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
