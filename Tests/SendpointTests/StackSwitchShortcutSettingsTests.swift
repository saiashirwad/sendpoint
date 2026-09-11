import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class StackSwitchShortcutSettingsTests: XCTestCase {
    func testTheShiftVariantOfTheSwitchShortcutIsClaimed() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let shiftU = KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift])
            XCTAssertEqual(settings.shortcutConflict(for: shiftU, excluding: .clear), .duplicate(.switchStack))
            XCTAssertThrowsError(try settings.setShortcut(shiftU, for: .nextStack))

            // And the other way round: a switch shortcut whose ⇧ variant is taken.
            try settings.setShortcut(
                KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift]), for: .clear)
            XCTAssertEqual(
                settings.shortcutConflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.command]),
                    excluding: .switchStack),
                .duplicate(.clear))
            XCTAssertEqual(
                settings.shortcutConflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command, .shift]),
                    excluding: .capture),
                nil, "only the switch shortcut claims its ⇧ variant")
        }
    }

    func testAShiftedSwitchShortcutHasNoReverse() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            try settings.setShortcut(KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift]),
                for: .switchStack)
            XCTAssertNil(settings.switchStackReverseCombo)
        }
    }

    func testOptionalSlotsCanBeSetAndClearedAndBothPersist() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let next = KeyCombo(keyCode: UInt16(kVK_ANSI_RightBracket), modifiers: [.command])
            try settings.setShortcut(next, for: .nextStack)
            XCTAssertEqual(settings.nextStackCombo, next)
            XCTAssertEqual(ShortcutSettings(defaults: defaults).nextStackCombo, next)

            settings.clearShortcut(for: .nextStack)
            XCTAssertNil(settings.nextStackCombo)
            XCTAssertNil(ShortcutSettings(defaults: defaults).nextStackCombo)
            settings.clearShortcut(for: .nextStack)

            settings.clearShortcut(for: .switchStack)
            XCTAssertNotNil(settings.combo(for: .switchStack), "required slots cannot be cleared")
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
