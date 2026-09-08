import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class StackSwitchShortcutSettingsTests: XCTestCase {
    func testSwitchDefaultsToCommandUWithShiftReverseAndStepKeysUnbound() {
        withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.switchSessionCombo, KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command]))
            XCTAssertEqual(settings.switchSessionReverseCombo,
                KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift]))
            XCTAssertNil(settings.nextStackCombo)
            XCTAssertNil(settings.previousStackCombo)
            XCTAssertNil(settings.combo(for: .nextStack))
            XCTAssertTrue(settings.shortcutRegistrationIssues.isEmpty)
        }
    }

    func testTheShiftVariantOfTheSwitchShortcutIsClaimed() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let shiftU = KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift])
            XCTAssertEqual(settings.shortcutConflict(for: shiftU, excluding: .clear), .duplicate(.switchSession))
            XCTAssertThrowsError(try settings.setShortcut(shiftU, for: .nextStack))

            // And the other way round: a switch shortcut whose ⇧ variant is taken.
            try settings.setShortcut(
                KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift]), for: .clear)
            XCTAssertEqual(
                settings.shortcutConflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command]),
                    excluding: .switchSession),
                .duplicate(.clear))
            XCTAssertEqual(
                settings.shortcutConflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command, .shift]),
                    excluding: .capture),
                nil, "only the switch shortcut claims its ⇧ variant")
        }
    }

    func testAShiftedSwitchShortcutHasNoReverse() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            try settings.setShortcut(KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift]),
                for: .switchSession)
            XCTAssertNil(settings.switchSessionReverseCombo)
        }
    }

    func testOptionalSlotsCanBeSetAndClearedAndBothPersist() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            let next = KeyCombo(keyCode: UInt16(kVK_ANSI_RightBracket), modifiers: [.command])
            var changes = 0
            settings.onHotKeysChanged = { changes += 1 }
            try settings.setShortcut(next, for: .nextStack)
            XCTAssertEqual(settings.nextStackCombo, next)
            XCTAssertEqual(AppSettings(defaults: defaults).nextStackCombo, next)

            settings.clearShortcut(for: .nextStack)
            XCTAssertNil(settings.nextStackCombo)
            XCTAssertNil(AppSettings(defaults: defaults).nextStackCombo)
            settings.clearShortcut(for: .nextStack)
            XCTAssertEqual(changes, 2, "clearing an already clear slot notifies nobody")

            settings.clearShortcut(for: .switchSession)
            XCTAssertNotNil(settings.combo(for: .switchSession), "required slots cannot be cleared")
            XCTAssertEqual(changes, 2)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointStackSwitchShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
