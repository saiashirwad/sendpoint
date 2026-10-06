import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class ShortcutCollisionTests: XCTestCase {
    func testDuplicateShortcutIsRejectedBeforePersistence() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        let oldClear = settings.clearCombo
        let oldStoredClear = defaults.data(forKey: "clearPreference")

        XCTAssertThrowsError(try settings.setShortcut(try XCTUnwrap(settings.copyCombo), for: .clear)) {
            XCTAssertEqual($0 as? ShortcutConflict, .duplicate(.copy))
        }
        XCTAssertEqual(settings.clearCombo, oldClear)
        XCTAssertEqual(defaults.data(forKey: "clearPreference"), oldStoredClear)
    }

    func testFixedMainMenuShortcutsAreRejected() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        let closeWindow = KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command])
        let undo = KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command])

        XCTAssertEqual(
            settings.shortcutConflict(for: closeWindow, excluding: .clear),
            .reserved("Close Window (⌘W)")
        )
        XCTAssertEqual(
            settings.shortcutConflict(for: undo, excluding: .clear),
            .reserved("Undo (⌘Z)")
        )
        XCTAssertThrowsError(try settings.setShortcut(closeWindow, for: .clear))
        XCTAssertThrowsError(try settings.setShortcut(undo, for: .clear))
    }

    func testStalePersistedConflictsRemainVisibleToRegistrationValidation() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reserved = KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command])
        let duplicate = KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command])
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(reserved)), forKey: "clearPreference")
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(duplicate)), forKey: "copyPreference")
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(duplicate)), forKey: "stackPreference")

        let settings = ShortcutSettings(defaults: defaults)

        XCTAssertNil(settings.copyCombo)
        XCTAssertNil(settings.stackCombo)
        XCTAssertNil(settings.clearCombo)

        XCTAssertEqual(
            settings.shortcutConflict(for: reserved, excluding: .clear),
            .reserved("Undo (⌘Z)")
        )
        XCTAssertEqual(
            settings.shortcutConflict(for: duplicate, excluding: .copy),
            .duplicate(.stack)
        )
        XCTAssertEqual(
            settings.configurationIssues,
            [
                .conflict(slot: .copy, combo: duplicate, reason: .duplicate(.stack)),
                .conflict(slot: .stack, combo: duplicate, reason: .duplicate(.copy)),
                .conflict(slot: .clear, combo: reserved, reason: .reserved("Undo (⌘Z)")),
            ]
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SendpointShortcutCollisionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
