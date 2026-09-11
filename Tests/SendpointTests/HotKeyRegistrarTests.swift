import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class HotKeyRegistrarTests: XCTestCase {
    func testStoredInvalidComboYieldsInvalidAndIsNotRegistered() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [])
        defaults.set(try JSONEncoder().encode(invalid), forKey: "captureCombo")
        let settings = AppSettings(defaults: defaults)
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
        let settings = AppSettings(defaults: defaults)
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
        let settings = AppSettings(defaults: defaults)
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

    func testReverseSwitchIsClaimedOnlyAfterThePrimarySwitchSucceeds() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        var calls: [(keyCode: UInt32, modifiers: UInt32)] = []
        let succeeding = HotKeyCenter(
            registerEvent: { keyCode, carbonModifiers, _ in
                calls.append((keyCode, carbonModifiers))
                return (noErr, EventHotKeyRef(bitPattern: 1))
            },
            unregisterEvent: { _ in }
        )
        let registrar = HotKeyRegistrar(settings: settings, center: succeeding)

        let issues = registrar.register(makeActions())

        XCTAssertTrue(issues.isEmpty)
        let reverse = try XCTUnwrap(settings.switchSessionReverseCombo)
        let shiftCalls = calls.filter { $0.modifiers & UInt32(shiftKey) != 0 }
        XCTAssertEqual(shiftCalls.count, 1)
        XCTAssertEqual(shiftCalls.first?.keyCode, UInt32(reverse.keyCode))
        XCTAssertEqual(shiftCalls.first?.modifiers, reverse.carbonModifiers)
        let primaryIndex = try XCTUnwrap(calls.firstIndex {
            $0.keyCode == UInt32(settings.switchSessionCombo.keyCode)
                && $0.modifiers == settings.switchSessionCombo.carbonModifiers
        })
        let reverseIndex = try XCTUnwrap(calls.firstIndex { $0.modifiers & UInt32(shiftKey) != 0 })
        XCTAssertGreaterThan(reverseIndex, primaryIndex)

        var failingModifiers: [UInt32] = []
        let failing = HotKeyCenter(
            registerEvent: { _, carbonModifiers, _ in
                failingModifiers.append(carbonModifiers)
                guard carbonModifiers & UInt32(shiftKey) == 0 else {
                    return (noErr, EventHotKeyRef(bitPattern: 1))
                }
                return (OSStatus(-1), nil)
            },
            unregisterEvent: { _ in }
        )
        let secondRegistrar = HotKeyRegistrar(settings: settings, center: failing)

        _ = secondRegistrar.register(makeActions())

        XCTAssertTrue(failingModifiers.contains { $0 == settings.switchSessionCombo.carbonModifiers })
        XCTAssertEqual(failingModifiers.filter { $0 & UInt32(shiftKey) != 0 }.count, 0)
    }

    func testUnregisterAllReleasesEveryRegisteredName() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
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

        // Temporary cycle keys owned by the switcher and the capture panel.
        center.registerRaw(name: .voiceEscape, keyCode: UInt16(kVK_Escape), carbonModifiers: 0, pressed: {})
        center.registerRaw(name: .switchEscape, keyCode: UInt16(kVK_Escape), carbonModifiers: 0, pressed: {})
        center.registerRaw(name: .switchPinUp, keyCode: UInt16(kVK_UpArrow),
                           carbonModifiers: UInt32(optionKey), pressed: {})
        center.registerRaw(name: .switchPinDown, keyCode: UInt16(kVK_DownArrow),
                           carbonModifiers: UInt32(optionKey), pressed: {})

        registrar.unregisterAll()

        XCTAssertGreaterThan(successfulRegistrations, 0)
        XCTAssertEqual(unregisteredRefs.count, successfulRegistrations)
    }

    private func makeActions() -> HotKeyRegistrar.Actions {
        HotKeyRegistrar.Actions(
            voicePressed: {},
            voiceReleased: {},
            typedNote: {},
            copy: {},
            showStack: {},
            switchStack: { _ in },
            nextStack: {},
            previousStack: {},
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
