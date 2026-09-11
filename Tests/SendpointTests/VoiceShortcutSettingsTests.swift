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
            let combo = KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option])
            try shortcuts.setShortcut(combo, for: .voiceCapture)
            voice.setVoiceMode(.tap)
            XCTAssertEqual(ShortcutSettings(defaults: defaults).voiceCaptureCombo, combo)
            XCTAssertEqual(VoiceSettings(defaults: defaults).voiceMode, .tap)
            voice.setVoiceMode(.hold)
            XCTAssertEqual(VoiceSettings(defaults: defaults).voiceMode, .hold)
        }
    }

    func testUnknownModeFallsBackToHold() {
        withDefaults { defaults in
            defaults.set("automatic", forKey: "voiceMode")
            XCTAssertEqual(VoiceSettings(defaults: defaults).voiceMode, .hold)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointVoiceShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
