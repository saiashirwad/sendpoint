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
        XCTAssertEqual(center.register(name: .slot(.voiceCapture), combo: combo,
            released: { events.append("release") }, action: { events.append("press") }), .registered)
        let original = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])

        XCTAssertEqual(center.register(name: .slot(.voiceCapture), combo: combo,
            released: { events.append("new release") }, action: { events.append("new press") }), .registered)
        let replacement = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])
        center.fire(id: replacement, released: false)
        center.fire(id: replacement, released: true)
        XCTAssertEqual(events, ["press", "release", "new press", "new release"])
        center.unregister(name: .slot(.voiceCapture))
        center.unregister(name: .slot(.voiceCapture))
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
        XCTAssertEqual(center.register(name: .slot(.capture), combo: combo) { presses += 1 }, .registered)
        center.fire(id: id, released: true)
        XCTAssertEqual(presses, 0)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(center.register(name: .slot(.capture), combo: nil) { presses += 1 }, .invalid)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(unregistered, 1)
    }

    func testRouteDispatchesEachIDToItsRegisteringCenter() {
        var ids: [UInt32] = []
        var pressesA: [Int] = []
        var pressesB = 0
        let stub: HotKeyCenter.RegisterEvent = { _, _, id in
            ids.append(id.id)
            return (noErr, EventHotKeyRef(bitPattern: Int(id.id)))
        }
        let centerA = HotKeyCenter(registerEvent: stub, unregisterEvent: { _ in })
        let centerB = HotKeyCenter(registerEvent: stub, unregisterEvent: { _ in })
        let comboA = KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command])
        let comboB = KeyCombo(keyCode: UInt16(kVK_ANSI_B), modifiers: [.command])
        XCTAssertEqual(centerA.register(name: .slot(.capture), combo: comboA) { pressesA.append(1) }, .registered)
        XCTAssertEqual(centerA.register(name: .slot(.copy), combo: comboB) { pressesA.append(2) }, .registered)
        XCTAssertEqual(centerB.register(name: .slot(.capture), combo: comboA) { pressesB += 1 }, .registered)
        XCTAssertEqual(Set(ids).count, 3, "ids are unique across centers")
        HotKeyCenter.route(id: ids[1], released: false)
        XCTAssertEqual(pressesA, [2])
        XCTAssertEqual(pressesB, 0)
        HotKeyCenter.route(id: ids[0], released: false)
        XCTAssertEqual(pressesA, [2, 1])
        XCTAssertEqual(pressesB, 0)
        HotKeyCenter.route(id: ids[2], released: false)
        XCTAssertEqual(pressesB, 1)
        centerB.unregister(name: .slot(.capture))
        HotKeyCenter.route(id: ids[2], released: false)
        XCTAssertEqual(pressesA, [2, 1], "stale events for an unregistered id are dropped")
        XCTAssertEqual(pressesB, 1)
    }
}
