import AppKit
import Carbon.HIToolbox
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StackShortcutSettingsTests: XCTestCase {
    func testEveryStackHasAShortcutOnTheHomeRowUnderOption() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let keys = [kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon]

            XCTAssertEqual(ShortcutSlot.selectStackCases.count, StackDocument.stackCount)
            for (number, key) in zip(1..., keys) {
                XCTAssertEqual(
                    settings.selectStackCombo(number),
                    KeyCombo(keyCode: UInt16(key), modifiers: [.option]),
                    "stack \(number)"
                )
            }
            XCTAssertTrue(settings.shortcutRegistrationIssues.isEmpty)
        }
    }

    func testAStackShortcutCannotTakeAnotherStacksKey() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let optionJ = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option])

            XCTAssertEqual(
                settings.shortcutConflict(for: optionJ, excluding: .selectStack(1)),
                .duplicate(.selectStack(2))
            )
            XCTAssertThrowsError(try settings.setShortcut(optionJ, for: .clear))
            XCTAssertNil(settings.shortcutConflict(for: optionJ, excluding: .selectStack(2)))
        }
    }

    func testMovingANoteIsTheStacksShortcutWithShiftAndIsClaimedWithIt() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let optionShiftJ = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option, .shift])

            XCTAssertEqual(settings.moveNoteCombo(2), optionShiftJ)
            XCTAssertEqual(settings.moveNoteStackNumber(for: optionShiftJ), 2)
            XCTAssertNil(settings.moveNoteStackNumber(for: KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option])))
            XCTAssertEqual(settings.shortcutConflict(for: optionShiftJ, excluding: .clear), .duplicate(.selectStack(2)))

            let replacement = KeyCombo(keyCode: UInt16(kVK_ANSI_2), modifiers: [.control, .shift])
            try settings.setShortcut(replacement, for: .selectStack(2))
            XCTAssertNil(settings.moveNoteCombo(2), "a shortcut that already holds shift has no move variant")
            XCTAssertNil(settings.moveNoteStackNumber(for: optionShiftJ))

            settings.clearShortcut(for: .selectStack(3))
            XCTAssertNil(settings.moveNoteCombo(3))
        }
    }

    func testStackShortcutsCanBeReboundAndClearedAndBothPersist() throws {
        try withDefaults { defaults in
            let settings = ShortcutSettings(defaults: defaults)
            let replacement = KeyCombo(keyCode: UInt16(kVK_ANSI_3), modifiers: [.control, .option])
            try settings.setShortcut(replacement, for: .selectStack(3))
            XCTAssertEqual(settings.selectStackCombo(3), replacement)
            XCTAssertEqual(ShortcutSettings(defaults: defaults).selectStackCombo(3), replacement)

            settings.clearShortcut(for: .selectStack(3))
            XCTAssertNil(settings.selectStackCombo(3))
            XCTAssertNil(ShortcutSettings(defaults: defaults).selectStackCombo(3))
            settings.clearShortcut(for: .selectStack(3))

            settings.clearShortcut(for: .stack)
            XCTAssertNotNil(settings.combo(for: .stack), "required slots cannot be cleared")
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "SendpointStackShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
