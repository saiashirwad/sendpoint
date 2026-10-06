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
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(invalid)), forKey: "capturePreference")
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

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(settings.configurationIssues, [.invalid(slot: .capture, combo: invalid)])
        XCTAssertNil(settings.captureCombo)
        XCTAssertFalse(
            attempts.contains { $0.keyCode == UInt32(invalid.keyCode) && $0.modifiers == invalid.carbonModifiers }
        )
    }

    func testSharedStoredComboConflictsForBothSlotsWithoutRegistration() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command])
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(shared)), forKey: "copyPreference")
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(shared)), forKey: "stackPreference")
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

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(settings.configurationIssues, [
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
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(optionH)), forKey: "capturePreference")
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(optionShiftJ)), forKey: "copyPreference")
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
        let displaced: [ShortcutConfigurationIssue] = [
            .displaced(slot: .selectStack(1), combo: optionH, by: .capture),
            .displaced(slot: .selectStack(2),
                       combo: KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option]), by: .copy),
        ]

        XCTAssertEqual(settings.captureCombo, optionH)
        XCTAssertNil(settings.selectStackCombo(1))
        XCTAssertNil(settings.selectStackCombo(2))
        XCTAssertNotNil(settings.selectStackCombo(3))
        XCTAssertEqual(settings.configurationIssues, displaced)
        XCTAssertTrue(registrar.register(makeActions()).isEmpty)
        for kept in [optionH, optionShiftJ] {
            XCTAssertEqual(
                attempts.filter { $0.keyCode == UInt32(kept.keyCode) && $0.modifiers == kept.carbonModifiers }.count, 1
            )
        }

        let replacement = KeyCombo(keyCode: UInt16(kVK_ANSI_1), modifiers: [.control, .option])
        try registrar.rebind(replacement, for: .selectStack(1))
        XCTAssertEqual(settings.configurationIssues, [displaced[1]])

        let freed = KeyCombo(keyCode: UInt16(kVK_ANSI_2), modifiers: [.control, .option])
        try registrar.rebind(freed, for: .copy)
        XCTAssertEqual(settings.selectStackCombo(2), KeyCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.option]),
            "the default goes live as soon as its owner lets go of the key")
        XCTAssertEqual(settings.configurationIssues, [])
    }

    func testADisplacedDefaultCanBeLeftUnboundForGood() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let optionH = KeyCombo(keyCode: UInt16(kVK_ANSI_H), modifiers: [.option])
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(optionH)), forKey: "capturePreference")
        let settings = ShortcutSettings(defaults: defaults)
        let registrar = HotKeyRegistrar(settings: settings, center: HotKeyCenter(
            registerEvent: { _, _, _ in (noErr, EventHotKeyRef(bitPattern: 1)) },
            unregisterEvent: { _ in }
        ))
        XCTAssertTrue(registrar.register(makeActions()).isEmpty)
        XCTAssertEqual(settings.configurationIssues,
            [.displaced(slot: .selectStack(1), combo: optionH, by: .capture)])

        registrar.clear(.selectStack(1))
        XCTAssertEqual(settings.configurationIssues, [])
        XCTAssertEqual(ShortcutSettings(defaults: defaults).configurationIssues, [],
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

        let expected: [ShortcutRegistrationFailure] = ShortcutSlot.allCases.compactMap { slot in
            guard let combo = settings.combo(for: slot) else { return nil }
            return ShortcutRegistrationFailure(slot: slot, combo: combo, status: status)
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

    func testHoldShortcutsDispatchBothPressAndReleaseAndStopAfterTeardown() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        var ids: [KeyCombo: UInt32] = [:]
        let center = HotKeyCenter(registerEvent: { key, modifiers, id in
            for slot in [ShortcutSlot.voiceCapture, .dictate] {
                if let combo = settings.combo(for: slot), UInt32(combo.keyCode) == key,
                   combo.carbonModifiers == modifiers { ids[combo] = id.id }
            }
            return (noErr, EventHotKeyRef(bitPattern: 1))
        }, unregisterEvent: { _ in })
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        var events: [String] = []
        var actions = makeActions()
        actions.voicePressed = { events.append("voice pressed") }
        actions.voiceReleased = { events.append("voice released") }
        actions.dictatePressed = { events.append("dictate pressed") }
        actions.dictateReleased = { events.append("dictate released") }
        registrar.register(actions)
        for slot in [ShortcutSlot.voiceCapture, .dictate] {
            let id = try XCTUnwrap(ids[try XCTUnwrap(settings.combo(for: slot))])
            center.fire(id: id, released: false)
            center.fire(id: id, released: true)
        }
        XCTAssertEqual(events, ["voice pressed", "voice released", "dictate pressed", "dictate released"])
        registrar.unregisterAll()
        for id in ids.values { center.fire(id: id, released: false) }
        XCTAssertEqual(events.count, 4)
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

    func testLatestNoteShortcutFiresCanBeClearedAndYieldsToExistingBindings() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: [.control, .command])
        let settings = ShortcutSettings(defaults: defaults)
        XCTAssertEqual(settings.combo(for: .editLatest), combo)
        var registeredID: UInt32?
        let center = HotKeyCenter(registerEvent: { key, modifiers, id in
            if key == UInt32(combo.keyCode), modifiers == combo.carbonModifiers { registeredID = id.id }
            return (noErr, EventHotKeyRef(bitPattern: 1))
        }, unregisterEvent: { _ in })
        let registrar = HotKeyRegistrar(settings: settings, center: center)
        var fired = 0
        var actions = makeActions()
        actions.editLatest = { fired += 1 }
        XCTAssertTrue(registrar.register(actions).isEmpty)
        center.fire(id: try XCTUnwrap(registeredID), released: false)
        XCTAssertEqual(fired, 1)
        registrar.clear(.editLatest)
        XCTAssertNil(ShortcutSettings(defaults: defaults).combo(for: .editLatest))
        defaults.removeObject(forKey: "editLatestPreference")
        defaults.set(try JSONEncoder().encode(ShortcutPreference.custom(combo)), forKey: "capturePreference")
        let restored = ShortcutSettings(defaults: defaults)
        XCTAssertEqual(restored.captureCombo, combo)
        XCTAssertNil(restored.combo(for: .editLatest))
        XCTAssertEqual(restored.configurationIssues,
                       [.displaced(slot: .editLatest, combo: combo, by: .capture)])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SendpointHotKeyRegistrarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
