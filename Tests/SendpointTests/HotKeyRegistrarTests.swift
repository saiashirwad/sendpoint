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

    func testAPersistedBindingKeepsItsKeyWhenANewStackDefaultWantsIt() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let optionH = KeyCombo(keyCode: UInt16(kVK_ANSI_H), modifiers: [.option])
        let optionShiftJ = KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option, .shift])
        defaults.set(try JSONEncoder().encode(optionH), forKey: "captureCombo")
        defaults.set(try JSONEncoder().encode(optionShiftJ), forKey: "copyCombo")
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
        let displaced: [ShortcutRegistrationIssue] = [
            .displaced(slot: .selectStack(1), combo: optionH, by: .capture),
            .displaced(slot: .selectStack(2),
                       combo: KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option]), by: .copy),
        ]

        XCTAssertEqual(settings.captureCombo, optionH)
        XCTAssertNil(settings.selectStackCombo(1))
        XCTAssertNil(settings.selectStackCombo(2))
        XCTAssertNotNil(settings.selectStackCombo(3))
        XCTAssertEqual(settings.shortcutRegistrationIssues, displaced)
        XCTAssertEqual(registrar.register(makeActions()), displaced)
        for kept in [optionH, optionShiftJ] {
            XCTAssertEqual(
                attempts.filter { $0.keyCode == UInt32(kept.keyCode) && $0.modifiers == kept.carbonModifiers }.count, 1
            )
        }

        let replacement = KeyCombo(keyCode: UInt16(kVK_ANSI_1), modifiers: [.control, .option])
        try registrar.rebind(replacement, for: .selectStack(1))
        XCTAssertEqual(settings.shortcutRegistrationIssues, [displaced[1]])

        let freed = KeyCombo(keyCode: UInt16(kVK_ANSI_2), modifiers: [.control, .option])
        try registrar.rebind(freed, for: .copy)
        XCTAssertEqual(settings.selectStackCombo(2), KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option]),
            "the default goes live as soon as its owner lets go of the key")
        XCTAssertEqual(settings.shortcutRegistrationIssues, [])
    }

    func testADisplacedDefaultCanBeLeftUnboundForGood() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let optionH = KeyCombo(keyCode: UInt16(kVK_ANSI_H), modifiers: [.option])
        defaults.set(try JSONEncoder().encode(optionH), forKey: "captureCombo")
        let settings = ShortcutSettings(defaults: defaults)
        let registrar = HotKeyRegistrar(settings: settings, center: HotKeyCenter(
            registerEvent: { _, _, _ in (noErr, EventHotKeyRef(bitPattern: 1)) },
            unregisterEvent: { _ in }
        ))
        XCTAssertEqual(registrar.register(makeActions()),
            [.displaced(slot: .selectStack(1), combo: optionH, by: .capture)])

        registrar.clear(.selectStack(1))
        XCTAssertEqual(settings.shortcutRegistrationIssues, [])
        XCTAssertEqual(ShortcutSettings(defaults: defaults).shortcutRegistrationIssues, [],
            "the choice survives a relaunch")
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
