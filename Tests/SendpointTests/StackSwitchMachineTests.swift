import Foundation
import XCTest
@testable import Sendpoint

final class StackSwitchMachineTests: XCTestCase {
    private let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    /// `a` is current; `b` was used just before it; `c` is the oldest.
    private var orders: StackSwitchOrders {
        StackSwitchOrders(recent: [a, b, c], listed: [c, a, b])
    }

    func testTapAndReleaseSwitchesToTheStackUsedLast() {
        var machine = StackSwitchMachine()
        XCTAssertEqual(machine.handle(.press(reverse: false), orders: orders), [.showPreview])
        XCTAssertEqual(machine.state, .cycling)
        XCTAssertEqual(machine.order, [c, a, b], "the palette keeps the listed order so rows stay put")
        XCTAssertEqual(machine.highlight, b, "the first press lights the stack used last")

        XCTAssertEqual(machine.handle(.release, orders: orders), [.switchTo(b), .hidePreview])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.highlight)
        XCTAssertEqual(machine.handle(.release, orders: orders), [], "a second release is inert")
        XCTAssertEqual(machine.handle(.lingerElapsed, orders: orders), [])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.highlight)
    }

    func testHeldPressesWalkDownTheListFromTheLitRowAndShiftWalksUp() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.highlight, b, "b is the last row")
        XCTAssertEqual(machine.handle(.press(reverse: false), orders: orders), [])
        XCTAssertEqual(machine.highlight, c, "wraps to the top row")
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.highlight, a, "the current stack is a row like any other")
        _ = machine.handle(.press(reverse: true), orders: orders)
        XCTAssertEqual(machine.highlight, c)
        XCTAssertEqual(machine.handle(.release, orders: orders), [.switchTo(c), .hidePreview])
    }

    func testReversePressFromIdleLightsTheRowAboveTheCurrentStack() {
        var machine = StackSwitchMachine()
        XCTAssertEqual(machine.handle(.press(reverse: true), orders: orders), [.showPreview])
        XCTAssertEqual(machine.highlight, c, "a is current in row two, so ⇧ lights row one")

        // Current at the top wraps to the bottom.
        var wrapped = StackSwitchMachine()
        _ = wrapped.handle(.press(reverse: true), orders: StackSwitchOrders(recent: [c, a, b], listed: [c, a, b]))
        XCTAssertEqual(wrapped.highlight, b)
    }

    func testNextCycleStartsFromTheNewCurrentStack() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        _ = machine.handle(.release, orders: orders)
        // The switch to b committed: b is current, a is what was used before.
        let after = StackSwitchOrders(recent: [b, a, c], listed: [c, a, b])
        XCTAssertEqual(machine.handle(.press(reverse: false), orders: after), [.showPreview],
            "each hold opens a new preview")
        XCTAssertEqual(machine.state, .cycling)
        XCTAssertEqual(machine.order, [c, a, b], "rows do not move between openings")
        XCTAssertEqual(machine.highlight, a, "a second tap toggles straight back")
    }

    func testEscapeCancelsWithoutSwitching() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.handle(.escape, orders: orders), [.hidePreview])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.release, orders: orders), [], "the release that follows does nothing")
        XCTAssertEqual(machine.handle(.escape, orders: orders), [], "escape outside a cycle is inert")
    }

    func testPinHandsTheLitStackToThePalette() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.handle(.pin, orders: orders), [.hidePreview, .openPalette(highlighting: c)])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.release, orders: orders), [])
        XCTAssertEqual(machine.handle(.pin, orders: orders), [], "pin outside a cycle is inert")
    }

    func testStepWalksTheListedOrderAndSwitchesAtOnce() {
        var machine = StackSwitchMachine()
        XCTAssertEqual(machine.handle(.step(1), orders: orders), [.showPreview, .switchTo(b), .startLinger])
        XCTAssertEqual(machine.state, .lingering)
        XCTAssertEqual(machine.order, [c, a, b], "the palette shows the listed order for a step")
        XCTAssertEqual(machine.highlight, b)

        // b committed. Stepping again while the preview lingers keeps it up.
        let after = StackSwitchOrders(recent: [b, a, c], listed: [c, a, b])
        XCTAssertEqual(machine.handle(.step(1), orders: after), [.switchTo(c), .startLinger])
        XCTAssertEqual(machine.highlight, c)

        var backwards = StackSwitchMachine()
        XCTAssertEqual(backwards.handle(.step(-1), orders: orders), [.showPreview, .switchTo(c), .startLinger])
    }

    func testStepIsIgnoredWhileCycling() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.handle(.step(1), orders: orders), [])
        XCTAssertEqual(machine.highlight, b)
    }

    func testASingleStackOnlyBeeps() {
        let lonely = StackSwitchOrders(recent: [a], listed: [a])
        var machine = StackSwitchMachine()
        XCTAssertEqual(machine.handle(.press(reverse: false), orders: lonely), [.beep])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.step(1), orders: lonely), [.beep])
        XCTAssertEqual(machine.handle(.release, orders: lonely), [])
    }

    func testOrdersChangingMidCycleKeepsTheLitStackOrItsPlace() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.highlight, c)

        // A new stack appeared: c still exists, so it stays lit.
        let grown = UUID()
        XCTAssertEqual(machine.handle(.ordersChanged,
            orders: StackSwitchOrders(recent: [a, b, c, grown], listed: [c, a, grown, b])), [])
        XCTAssertEqual(machine.order, [c, a, grown, b])
        XCTAssertEqual(machine.highlight, c)

        // c was deleted: the highlight falls to the same row.
        XCTAssertEqual(machine.handle(.ordersChanged,
            orders: StackSwitchOrders(recent: [a, b], listed: [a, b])), [])
        XCTAssertEqual(machine.order, [a, b])
        XCTAssertEqual(machine.highlight, a)

        // Only one stack left: nothing to choose between.
        XCTAssertEqual(machine.handle(.ordersChanged,
            orders: StackSwitchOrders(recent: [a], listed: [a])), [.hidePreview])
        XCTAssertEqual(machine.state, .idle)
    }

    func testOrdersChangingWhileLingeringLeavesTheConfirmationAlone() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.step(1), orders: orders)
        let after = StackSwitchOrders(recent: [b, a, c], listed: [c, a, b])
        XCTAssertEqual(machine.handle(.ordersChanged, orders: after), [])
        XCTAssertEqual(machine.order, [c, a, b], "the frozen list does not jump as the switch commits")
        XCTAssertEqual(machine.highlight, b)
    }

    func testTeardownHidesAndIgnoresEverythingAfter() {
        var machine = StackSwitchMachine()
        _ = machine.handle(.press(reverse: false), orders: orders)
        XCTAssertEqual(machine.handle(.teardown, orders: orders), [.hidePreview])
        XCTAssertEqual(machine.state, .tornDown)
        XCTAssertEqual(machine.handle(.press(reverse: false), orders: orders), [])
        XCTAssertEqual(machine.handle(.release, orders: orders), [])
        XCTAssertEqual(machine.handle(.teardown, orders: orders), [])
    }
}
