import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class HotKeyCenterTests: XCTestCase {
    func testPressReleaseRoutingAndRebindingRejectOldRegistrationEvents() throws {
        var ids: [UInt32] = []
        var unregistered = 0
        let center = HotKeyCenter(registerEvent: { _, _, id in
            ids.append(id.id)
            return (noErr, EventHotKeyRef(bitPattern: Int(id.id)))
        }, unregisterEvent: { _ in unregistered += 1 })
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command])
        var events: [String] = []
        XCTAssertEqual(center.register(name: .voiceCapture, combo: combo,
            released: { events.append("release") }, action: { events.append("press") }), .registered)
        let original = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])

        XCTAssertEqual(center.register(name: .voiceCapture, combo: combo,
            released: { events.append("new release") }, action: { events.append("new press") }), .registered)
        let replacement = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])
        center.fire(id: replacement, released: false)
        center.fire(id: replacement, released: true)
        XCTAssertEqual(events, ["press", "release", "new press", "new release"])
        center.unregister(name: .voiceCapture)
        center.unregister(name: .voiceCapture)
        center.fire(id: replacement, released: false)
        center.fire(id: replacement, released: true)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(unregistered, 2)
    }

    func testPressOnlyShortcutIgnoresReleaseAndInvalidReplacementRemovesOldBinding() throws {
        var id: UInt32 = 0
        var unregistered = 0
        let center = HotKeyCenter(registerEvent: { _, _, hotKey in
            id = hotKey.id
            return (noErr, EventHotKeyRef(bitPattern: Int(id)))
        }, unregisterEvent: { _ in unregistered += 1 })
        let combo = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command])
        var presses = 0
        XCTAssertEqual(center.register(name: .capture, combo: combo) { presses += 1 }, .registered)
        center.fire(id: id, released: true)
        XCTAssertEqual(presses, 0)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(center.register(name: .capture, combo: nil) { presses += 1 }, .invalid)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(unregistered, 1)
    }

    func testRouteDispatchesEachIDToItsRegisteringCenter() {
        var pressesA: [UInt32] = []
        var pressesB = 0
        func stub(_ base: Int) -> HotKeyCenter.RegisterEvent {
            { _, _, id in (noErr, EventHotKeyRef(bitPattern: base + Int(id.id))) }
        }
        let centerA = HotKeyCenter(registerEvent: stub(0), unregisterEvent: { _ in })
        let centerB = HotKeyCenter(registerEvent: stub(1000), unregisterEvent: { _ in })
        let comboA = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command])
        let comboB = KeyCombo(keyCode: UInt16(kVK_ANSI_B), modifiers: [.command])
        XCTAssertEqual(centerA.register(name: .capture, combo: comboA) { pressesA.append(1) }, .registered)
        XCTAssertEqual(centerA.register(name: .copy, combo: comboB) { pressesA.append(2) }, .registered)
        // B's own id sequence restarts at 1 and claims the shared route for
        // that id, mirroring Carbon's single global id namespace.
        XCTAssertEqual(centerB.register(name: .capture, combo: comboA) { pressesB += 1 }, .registered)
        HotKeyCenter.route(id: 2, released: false)
        XCTAssertEqual(pressesA, [2])
        XCTAssertEqual(pressesB, 0)
        HotKeyCenter.route(id: 1, released: false)
        XCTAssertEqual(pressesA, [2])
        XCTAssertEqual(pressesB, 1)
        centerB.unregister(name: .capture)
        HotKeyCenter.route(id: 1, released: false)
        XCTAssertEqual(pressesA, [2], "stale events for an unregistered id are dropped")
        XCTAssertEqual(pressesB, 1)
    }
}
