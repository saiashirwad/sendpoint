import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class SetupTourTests: XCTestCase {
    func testEachNewNoteMovesTheTourOneSlideOn() {
        let tour = SetupTour()
        XCTAssertEqual(tour.step, .voice)

        tour.send(.noteCount(7))
        XCTAssertEqual(tour.step, .voice, "the first sample is the baseline, not a note")
        tour.send(.noteCount(7))
        XCTAssertEqual(tour.step, .voice)

        tour.send(.noteCount(8))
        XCTAssertEqual(tour.step, .text)
        tour.send(.noteCount(9))
        XCTAssertEqual(tour.step, .stack)
        tour.send(.noteCount(10))
        XCTAssertEqual(tour.step, .stack, "the stack slide waits for the stack, not a note")
    }

    func testOpeningTheStackLeadsToTheLastWordOnlyFromTheStackSlide() {
        let tour = SetupTour()
        tour.send(.openedStack)
        XCTAssertEqual(tour.step, .voice)
        tour.send(.skip)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .stack)
        tour.send(.openedStack)
        XCTAssertEqual(tour.step, .done)
        tour.send(.openedStack)
        XCTAssertEqual(tour.step, .done)
    }

    func testClearingNotesRebasesWithoutAdvancing() {
        let tour = SetupTour()
        tour.send(.noteCount(3))
        tour.send(.noteCount(0))
        XCTAssertEqual(tour.step, .voice)
        tour.send(.noteCount(1))
        XCTAssertEqual(tour.step, .text, "one note after the clear still counts")
    }

    func testSkipMovesOnAndStopsAtTheEnd() {
        let tour = SetupTour()
        tour.send(.skip)
        XCTAssertEqual(tour.step, .text)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .stack)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .done)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .done)
    }

    func testCopyNamesTheUsersOwnShortcutsOnOneLine() throws {
        let keys = SetupTourKeys(voice: "⌘E", capture: "⌘G", stack: "⌃⌘S", copy: "⌃⌘V")
        XCTAssertEqual(
            SetupTour.Step.voice.detail(keys: keys, voiceMode: .hold),
            "Select the line below, hold ⌘E, speak, let go."
        )
        XCTAssertEqual(
            SetupTour.Step.voice.detail(keys: keys, voiceMode: .tap),
            "Select the line below, press ⌘E, speak, press it again."
        )
        XCTAssertEqual(
            SetupTour.Step.text.detail(keys: keys, voiceMode: .hold),
            "Select the line below, press ⌘G, type, then ⌘↩."
        )
        XCTAssertEqual(
            SetupTour.Step.stack.detail(keys: keys, voiceMode: .hold),
            "⌃⌘S opens it any time. ⌃⌘V copies everything."
        )
        for step in SetupTour.Step.allCases {
            XCTAssertLessThan(step.detail(keys: keys, voiceMode: .tap).count, 64)
            XCTAssertLessThan(step.headline.count, 34)
        }
        XCTAssertEqual(
            SetupTour.Step.done.detail(keys: keys, voiceMode: .hold),
            "It lives in the menu bar. Settings are there too."
        )
        XCTAssertEqual(SetupTour.Step.railNames, ["Voice note", "Typed note", "Stack"])

        let voice = try XCTUnwrap(SetupTour.Step.voice.passage)
        let text = try XCTUnwrap(SetupTour.Step.text.passage)
        XCTAssertNotEqual(voice, text, "a fresh passage means a fresh selection")
        XCTAssertNil(SetupTour.Step.stack.passage)
        XCTAssertNil(SetupTour.Step.done.passage)
        for passage in [voice, text] { XCTAssertLessThan(passage.count, 125) }
    }

    func testNoteCountSpansEveryStack() async throws {
        let stacks = [
            Stack(name: "A", notes: [Note(subject: .standalone, body: "1")]),
            Stack(name: "B", notes: [
                Note(subject: .standalone, body: "2"),
                Note(subject: .selection(quote: "q"), body: "3"),
            ]),
        ]
        let document = StackDocument(stacks: stacks, currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        XCTAssertEqual(SetupTour.noteCount(in: store), 3)
    }
}
