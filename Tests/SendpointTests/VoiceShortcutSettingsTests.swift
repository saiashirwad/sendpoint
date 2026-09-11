import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class VoiceShortcutSettingsTests: XCTestCase {
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

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointVoiceShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
