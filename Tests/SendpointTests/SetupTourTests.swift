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
        XCTAssertEqual(tour.step, .send)
        tour.send(.noteCount(10))
        XCTAssertEqual(tour.step, .send, "the last slide waits for Done")
    }

    func testClearingNotesRebasesWithoutAdvancing() {
        let tour = SetupTour()
        tour.send(.noteCount(3))
        tour.send(.noteCount(0))
        XCTAssertEqual(tour.step, .voice)
        tour.send(.noteCount(1))
        XCTAssertEqual(tour.step, .text, "one note after the clear still counts")
    }

    func testNotesCapturedWhileSetupWasClosedDoNotAdvanceTheTour() {
        let tour = SetupTour()
        tour.send(.noteCount(3))
        tour.send(.presented)
        tour.send(.noteCount(5))
        XCTAssertEqual(tour.step, .voice, "reopening takes a fresh baseline")
        tour.send(.noteCount(6))
        XCTAssertEqual(tour.step, .text)
    }

    func testSkipMovesOnAndStopsAtTheEnd() {
        let tour = SetupTour()
        tour.send(.skip)
        XCTAssertEqual(tour.step, .text)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .send)
        tour.send(.skip)
        XCTAssertEqual(tour.step, .send)
    }

    func testCopyNamesTheUsersOwnShortcutsOnOneLine() throws {
        let keys = SetupTourKeys(voice: "⌘E", capture: "⌘G", stack: "⌃⌘S", copy: "⌃⌘V", stacks: "⌥H ⌥J ⌥K ⌥L ⌥;")
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
            SetupTour.Step.send.detail(keys: keys, voiceMode: .hold),
            "⌃⌘V puts your notes into any chat, at the cursor."
        )
        for step in SetupTour.Step.allCases {
            XCTAssertLessThan(step.detail(keys: keys, voiceMode: .tap).count, 64)
            XCTAssertLessThan(step.headline.count, 34)
        }
        XCTAssertEqual(SetupTour.Step.railNames, ["Voice note", "Typed note", "Send"])
        XCTAssertEqual(
            SetupTour.Step.send.tip(keys: keys),
            "⌥H ⌥J ⌥K ⌥L ⌥; switch between five stacks.\n⌃⌘S shows the current stack."
        )
        let unbound = SetupTourKeys(voice: "⌘E", capture: "⌘G", stack: "⌃⌘S", copy: "⌃⌘V", stacks: "")
        XCTAssertEqual(SetupTour.Step.send.tip(keys: unbound), "⌃⌘S shows the current stack.")
        XCTAssertNil(SetupTour.Step.voice.tip(keys: keys))

        let voice = try XCTUnwrap(SetupTour.Step.voice.passage)
        let text = try XCTUnwrap(SetupTour.Step.text.passage)
        XCTAssertNotEqual(voice, text, "a fresh passage means a fresh selection")
        XCTAssertNil(SetupTour.Step.send.passage)
        for passage in [voice, text] { XCTAssertLessThan(passage.count, 125) }
    }

    func testNoteCountSpansEveryStack() async throws {
        let stacks = [
            Stack(notes: [Note(subject: .standalone, body: "1")]),
            Stack(notes: [
                Note(subject: .standalone, body: "2"),
                Note(subject: .selection(quote: "q"), body: "3"),
            ]),
        ]
        let document = StackDocument(stacks: filled(stacks), currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        XCTAssertEqual(SetupTour.noteCount(in: store), 3)
    }
}
