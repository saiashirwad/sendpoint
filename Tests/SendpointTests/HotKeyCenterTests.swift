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
        XCTAssertEqual(center.register(name: "voice", combo: combo,
            released: { events.append("release") }, action: { events.append("press") }), .registered)
        let original = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])

        XCTAssertEqual(center.register(name: "voice", combo: combo,
            released: { events.append("new release") }, action: { events.append("new press") }), .registered)
        let replacement = try XCTUnwrap(ids.last)
        center.fire(id: original, released: false)
        center.fire(id: original, released: true)
        XCTAssertEqual(events, ["press", "release"])
        center.fire(id: replacement, released: false)
        center.fire(id: replacement, released: true)
        XCTAssertEqual(events, ["press", "release", "new press", "new release"])
        center.unregister(name: "voice")
        center.unregister(name: "voice")
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
        XCTAssertEqual(center.register(name: "capture", combo: combo) { presses += 1 }, .registered)
        center.fire(id: id, released: true)
        XCTAssertEqual(presses, 0)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(center.register(name: "capture", combo: nil) { presses += 1 }, .invalid)
        center.fire(id: id, released: false)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(unregistered, 1)
    }
}
