import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class VoiceShortcutSettingsTests: XCTestCase {
    func testDefaultsAreCommandBacktickAndHold() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.voiceCaptureCombo,
                KeyCombo(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command]))
            XCTAssertEqual(settings.voiceMode, .hold)
            XCTAssertEqual(settings.combo(for: .voiceCapture), settings.voiceCaptureCombo)
            XCTAssertTrue(settings.shortcutRegistrationIssues.isEmpty)
        }
    }

    func testVoiceShortcutAndModeAreAssignableAndPersistAcrossLaunches() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let combo = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option])
            var changes = 0
            settings.onHotKeysChanged = { changes += 1 }
            try settings.setShortcut(combo, for: .voiceCapture)
            settings.setVoiceMode(.tap)
            settings.setVoiceMode(.tap)
            XCTAssertEqual(changes, 2)
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.voiceCaptureCombo, combo)
            XCTAssertEqual(reloaded.voiceMode, .tap)
            settings.setVoiceMode(.hold)
            XCTAssertEqual(AppSettings(defaults: defaults).voiceMode, .hold)
        }
    }

    func testUnknownModeFallsBackToHold() {
        withDefaults { defaults in
            defaults.set("automatic", forKey: "voiceMode")
            XCTAssertEqual(AppSettings(defaults: defaults).voiceMode, .hold)
        }
    }

    func testVoiceParticipatesInNormalCollisionValidation() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let original = settings.voiceCaptureCombo
            XCTAssertThrowsError(try settings.setShortcut(settings.captureCombo, for: .voiceCapture)) {
                XCTAssertEqual($0 as? ShortcutConflict, .duplicate(.capture))
            }
            XCTAssertThrowsError(try settings.setShortcut(original, for: .capture)) {
                XCTAssertEqual($0 as? ShortcutConflict, .duplicate(.voiceCapture))
            }
            XCTAssertEqual(settings.voiceCaptureCombo, original)
            XCTAssertNil(defaults.data(forKey: "voiceCaptureCombo"))
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointVoiceShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
