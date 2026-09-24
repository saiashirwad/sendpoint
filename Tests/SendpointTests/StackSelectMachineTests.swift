import Foundation
import XCTest
@testable import Sendpoint

final class StackSelectMachineTests: XCTestCase {
    private let stacks = (0..<5).map { _ in UUID() }

    func testSelectingAnotherStackSwitchesAndShowsItsReadout() {
        var machine = StackSelectMachine()
        XCTAssertEqual(send(.select(3), to: &machine), [
            .switchTo(stacks[2]), .showReadout(number: 3), .startTimer(generation: 1),
        ])
        XCTAssertEqual(machine.state, .showing(stacks[2], generation: 1))
    }

    func testSelectingTheCurrentStackStillQueuesTheSwitchSoTheLatestPressWins() {
        var machine = StackSelectMachine()
        XCTAssertEqual(send(.select(1), to: &machine), [
            .switchTo(stacks[0]), .showReadout(number: 1), .startTimer(generation: 1),
        ])
    }

    func testAnUnknownNumberBeepsAndChangesNothing() {
        var machine = StackSelectMachine()
        for number in [0, 6, -1] {
            XCTAssertEqual(send(.select(number), to: &machine), [.beep])
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testASurfaceThatNamesTheStackSuppressesTheReadoutAndTakesDownAnOldOne() {
        var machine = StackSelectMachine()
        XCTAssertEqual(send(.select(2), to: &machine, showsReadout: false), [.switchTo(stacks[1])])
        XCTAssertEqual(machine.state, .idle)

        _ = send(.select(3), to: &machine)
        XCTAssertEqual(send(.select(4), to: &machine, showsReadout: false), [.switchTo(stacks[3]), .hideReadout])
        XCTAssertEqual(machine.state, .idle)
    }

    func testOnlyTheLatestTimerTakesTheReadoutDown() {
        var machine = StackSelectMachine()
        _ = send(.select(2), to: &machine)
        _ = send(.select(3), to: &machine)
        XCTAssertEqual(machine.state, .showing(stacks[2], generation: 2))

        XCTAssertEqual(send(.readoutElapsed(generation: 1), to: &machine), [], "a stale timer is inert")
        XCTAssertEqual(machine.state, .showing(stacks[2], generation: 2))
        XCTAssertEqual(send(.readoutElapsed(generation: 2), to: &machine), [.hideReadout])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(send(.readoutElapsed(generation: 2), to: &machine), [])
    }

    func testAFailedSwitchTakesDownOnlyItsOwnReadout() {
        var machine = StackSelectMachine()
        _ = send(.select(2), to: &machine)
        XCTAssertEqual(send(.switchFailed(stacks[1]), to: &machine), [.hideReadout, .beep])
        XCTAssertEqual(machine.state, .idle)

        _ = send(.select(2), to: &machine)
        _ = send(.select(3), to: &machine)
        XCTAssertEqual(send(.switchFailed(stacks[1]), to: &machine), [.beep],
            "a later press already replaced the failed switch's readout")
        XCTAssertEqual(machine.state, .showing(stacks[2], generation: 3))
    }

    func testTeardownHidesOnceAndThenIgnoresEverything() {
        var machine = StackSelectMachine()
        _ = send(.select(2), to: &machine)
        XCTAssertEqual(send(.teardown, to: &machine), [.hideReadout])
        XCTAssertEqual(machine.state, .tornDown)
        XCTAssertEqual(send(.teardown, to: &machine), [])
        XCTAssertEqual(send(.select(3), to: &machine), [])
        XCTAssertEqual(send(.readoutElapsed(generation: 1), to: &machine), [])

        var idle = StackSelectMachine()
        XCTAssertEqual(send(.teardown, to: &idle), [], "nothing to hide")
    }

    private func send(
        _ event: StackSelectEvent, to machine: inout StackSelectMachine, showsReadout: Bool = true
    ) -> [StackSelectEffect] {
        machine.update(event, stacks: stacks, showsReadout: showsReadout)
    }
}
