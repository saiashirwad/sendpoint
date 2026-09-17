import AppKit
import Carbon.HIToolbox
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class HotKeyRegistrarTests: XCTestCase {
    func testStoredInvalidComboYieldsInvalidAndIsNotRegistered() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [])
        defaults.set(try JSONEncoder().encode(invalid), forKey: "captureCombo")
        let settings = ShortcutSettings(defaults: defaults)
        var attempts: [(keyCode: UInt32, modifiers: UInt32)] = []
        let center = HotKeyCenter(
            registerEvent: { keyCode, carbonModifiers, _ in
                attempts.append((keyCode, carbonModifiers))
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)

        let issues = registrar.register(makeActions())

        XCTAssertEqual(issues, [.invalid(slot: .capture, combo: invalid)])
        XCTAssertFalse(
            attempts.contains { $0.keyCode == UInt32(invalid.keyCode) && $0.modifiers == invalid.carbonModifiers }
        )
    }

    func testSharedStoredComboConflictsForBothSlotsWithoutRegistration() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command])
        defaults.set(try JSONEncoder().encode(shared), forKey: "copyCombo")
        defaults.set(try JSONEncoder().encode(shared), forKey: "stackCombo")
        let settings = ShortcutSettings(defaults: defaults)
        var attempts: [(keyCode: UInt32, modifiers: UInt32)] = []
        let center = HotKeyCenter(
            registerEvent: { keyCode, carbonModifiers, _ in
                attempts.append((keyCode, carbonModifiers))
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)

        let issues = registrar.register(makeActions())

        XCTAssertEqual(issues, [
            .conflict(slot: .copy, combo: shared, reason: .duplicate(.stack)),
            .conflict(slot: .stack, combo: shared, reason: .duplicate(.copy)),
        ])
        XCTAssertFalse(
            attempts.contains { $0.keyCode == UInt32(shared.keyCode) && $0.modifiers == shared.carbonModifiers }
        )
    }

    func testFailedRegistrationYieldsUnavailableForEveryBoundSlot() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        let status: Int32 = -9876
        var attempts = 0
        let center = HotKeyCenter(
            registerEvent: { _, _, _ in
                attempts += 1
                return (status, nil)
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)

        let issues = registrar.register(makeActions())

        let expected: [ShortcutRegistrationIssue] = ShortcutSlot.allCases.compactMap { slot in
            guard let combo = settings.combo(for: slot) else { return nil }
            return .unavailable(slot: slot, combo: combo, status: status)
        }
        XCTAssertEqual(issues, expected)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(attempts, expected.count)
    }

    func testEveryStackShortcutIsRegisteredAndReportsItsNumber() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        var ids: [UInt32: UInt32] = [:]
        let center = HotKeyCenter(
            registerEvent: { keyCode, _, hotKeyID in
                ids[keyCode] = hotKeyID.id
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        var selected: [Int] = []
        var actions = makeActions()
        actions.selectStack = { selected.append($0) }

        XCTAssertTrue(registrar.register(actions).isEmpty)

        for number in 1...StackDocument.stackCount {
            let combo = try XCTUnwrap(settings.selectStackCombo(number))
            center.fire(id: try XCTUnwrap(ids[UInt32(combo.keyCode)]), released: false)
        }
        XCTAssertEqual(selected, Array(1...StackDocument.stackCount))
    }

    func testUnregisterAllReleasesEveryRegisteredName() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        var successfulRegistrations = 0
        var unregisteredRefs: [EventHotKeyRef] = []
        let center = HotKeyCenter(
            registerEvent: { _, _, _ in
                successfulRegistrations += 1
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { ref in unregisteredRefs.append(ref) }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        registrar.register(makeActions())

        center.registerRaw(name: .voiceEscape, keyCode: UInt16(kVK_Escape), carbonModifiers: 0, pressed: {})

        registrar.unregisterAll()

        XCTAssertGreaterThan(successfulRegistrations, 0)
        XCTAssertEqual(unregisteredRefs.count, successfulRegistrations)
    }

    func testRebindPersistsAndRegistersTheReplacementImmediately() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        var attempts: [(UInt32, UInt32)] = []
        let center = HotKeyCenter(
            registerEvent: { keyCode, modifiers, _ in
                attempts.append((keyCode, modifiers))
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        _ = registrar.register(makeActions())
        let replacement = KeyCombo(
            keyCode: UInt16(kVK_ANSI_RightBracket),
            modifiers: [.control, .option]
        )

        try registrar.rebind(replacement, for: .selectStack(2))

        XCTAssertEqual(settings.selectStackCombo(2), replacement)
        XCTAssertEqual(ShortcutSettings(defaults: defaults).selectStackCombo(2), replacement)
        XCTAssertTrue(attempts.contains {
            $0.0 == UInt32(replacement.keyCode) && $0.1 == replacement.carbonModifiers
        })
    }

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

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SendpointHotKeyRegistrarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
