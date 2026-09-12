import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class PaletteWorkflowTests: XCTestCase {
    private let firstStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
    private let firstNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let secondNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let thirdNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    private let fourthNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!

    private var stacks: [Stack] {
        [
            Stack(id: firstStackID, name: "Reading", notes: [
                Note(id: firstNoteID, subject: .standalone, body: "One"),
                Note(id: secondNoteID, subject: .selection(quote: "quote"), body: "Two"),
                Note(id: thirdNoteID, subject: .standalone, body: "Three"),
            ]),
            Stack(id: secondStackID, name: "Writing", notes: [
                Note(id: fourthNoteID, subject: .standalone, body: "Four"),
            ]),
        ]
    }

    func testTabAndArrowsToggleFocusAndClearTheQuery() {
        var harness = makeHarness()
        harness.send(.open(.stacks, highlighting: firstStackID))
        XCTAssertEqual(harness.state.focusedPane, .stacks)

        harness.send(.query("rea"))
        harness.send(.key(.tab, textHasSelection: false))
        XCTAssertEqual(harness.state.focusedPane, .notes)
        XCTAssertEqual(harness.state.query, "", "flipping focus clears the query")

        harness.send(.key(.backTab, textHasSelection: false))
        XCTAssertEqual(harness.state.focusedPane, .stacks)

        harness.send(.query("rea"))
        XCTAssertFalse(harness.send(.key(.right, textHasSelection: false)),
            "a typed query keeps the arrow keys in the field")
        XCTAssertEqual(harness.state.focusedPane, .stacks)

        harness.send(.query(""))
        harness.send(.key(.right, textHasSelection: false))
        XCTAssertEqual(harness.state.focusedPane, .notes)
        harness.send(.key(.left, textHasSelection: false))
        XCTAssertEqual(harness.state.focusedPane, .stacks)
    }

    func testChoosingANoteFromTheSidebarMovesFocusAndClearsTheQuery() {
        var harness = makeHarness()
        harness.send(.open(.stacks, highlighting: firstStackID))
        harness.send(.query("rea"))

        harness.send(.chooseNote(secondNoteID))
        XCTAssertEqual(harness.state.focusedPane, .notes)
        XCTAssertEqual(harness.state.query, "", "the stack query must not become a note query")
        XCTAssertEqual(harness.state.noteState.highlight, secondNoteID)
    }

    func testOpenNotesHighlightsTheNewestNote() {
        var harness = makeHarness()
        harness.send(.open(.notes, highlighting: firstStackID))

        XCTAssertEqual(harness.state.focusedPane, .notes)
        XCTAssertEqual(harness.state.stackState.highlight, .stack(firstStackID))
        XCTAssertEqual(harness.state.noteState.highlight, thirdNoteID,
            "the show-stack path lands on the newest note")
    }

    func testSidebarArrowsPreviewEachStackAtItsNewestNote() {
        var harness = makeHarness()
        harness.send(.open(.stacks, highlighting: firstStackID))
        XCTAssertEqual(harness.state.noteState.highlight, thirdNoteID)

        harness.send(.key(.down, textHasSelection: false))
        XCTAssertEqual(harness.state.stackState.highlight, .stack(secondStackID))
        XCTAssertEqual(harness.state.noteState.highlight, fourthNoteID)

        harness.send(.key(.up, textHasSelection: false))
        XCTAssertEqual(harness.state.stackState.highlight, .stack(firstStackID))
        XCTAssertEqual(harness.state.noteState.highlight, thirdNoteID)
    }

    func testCommandDigitsSwitchStacksFromEitherPane() {
        var harness = makeHarness()
        harness.send(.open(.notes, highlighting: firstStackID))
        harness.send(.key(.commandDigit(2), textHasSelection: false))

        XCTAssertEqual(harness.mutation, .switchStack(stackID: secondStackID))
    }

    func testStackDeletedUnderTheNotePaneKeepsAPendingDraftUntilRejection() {
        var harness = makeHarness()
        harness.send(.open(.notes, highlighting: firstStackID))
        harness.send(.perform(.editNote(firstNoteID)))
        harness.send(.editText("changed"))
        harness.send(.commitEdit)

        guard let mutationID = harness.mutationID,
              case .saving = harness.state.interaction else {
            return XCTFail("committing a note draft must enqueue a mutation")
        }
        XCTAssertEqual(harness.mutation,
            .updateNoteBody(stackID: firstStackID, noteID: firstNoteID, body: "changed"))

        // The stack vanishes while the mutation is still out.
        harness.context = makeContext(stacks: Array(stacks.dropFirst()))
        harness.send(.documentChanged)

        XCTAssertEqual(harness.state.focusedPane, .notes, "the pane stays where it was")
        XCTAssertEqual(harness.state.stackState.highlight, .stack(secondStackID),
            "the sidebar falls back to a stack that still exists")
        XCTAssertEqual(harness.state.noteState.highlight, fourthNoteID,
            "the note pane follows the fallback stack")
        guard case let .saving(pending) = harness.state.interaction else {
            return XCTFail("a pending draft survives the document change")
        }
        XCTAssertEqual(pending.draft?.text, "changed")

        harness.send(.mutationResult(mutationID, .rejected("The target stack no longer exists.")))
        guard case let .failed(failed, message, retryable) = harness.state.interaction else {
            return XCTFail("the rejection must land in the failed state")
        }
        XCTAssertEqual(message, "The target stack no longer exists.")
        XCTAssertFalse(retryable)
        XCTAssertEqual(failed.draft?.text, "changed")

        harness.send(.cancelEdit)
        if case .failed = harness.state.interaction {
            XCTFail("dismissing a failed save must return to browsing")
        }
    }

    func testSearchScopeAndReturnActionFollowThePreviewedStackAndPane() {
        var harness = makeHarness()
        harness.send(.open(.stacks, highlighting: secondStackID))
        var projection = PaletteProjection(state: harness.state, context: harness.context)
        XCTAssertEqual(projection.searchPlaceholder, "Find or create a stack")
        XCTAssertEqual(projection.primaryAction?.action, .switchToStack(secondStackID))

        harness.send(.focusPane(.notes))
        projection = PaletteProjection(state: harness.state, context: harness.context)
        XCTAssertEqual(projection.searchPlaceholder, "Search notes in Writing")
        XCTAssertEqual(projection.primaryAction?.action, .editNote(fourthNoteID))
        harness.send(.query("One"))
        projection = PaletteProjection(state: harness.state, context: harness.context)
        XCTAssertTrue(projection.noteListing.notes.isEmpty, "Search must stay in the named stack")
        XCTAssertNil(projection.primaryAction, "An empty result must not advertise Return to edit")
    }

    // MARK: - Harness

    private func makeHarness() -> Harness {
        Harness(state: PaletteWorkflow(), context: makeContext(stacks: stacks))
    }

    private func makeContext(stacks: [Stack], currentStackID: UUID? = nil) -> PaletteContext {
        PaletteContext(
            stacks: stacks,
            currentStackID: currentStackID ?? stacks[0].id,
            lastCleared: nil,
            templates: [.plain],
            activeTemplate: .plain
        )
    }
}

@MainActor
private struct Harness {
    var state: PaletteWorkflow
    var context: PaletteContext
    private(set) var effects: [PaletteEffect] = []

    @discardableResult
    mutating func send(_ event: PaletteEvent) -> Bool {
        var update = PaletteUpdate(state: state, context: context, operationID: UUID(), now: Date())
        let handled = update.update(event)
        state = update.state
        effects = update.effects
        return handled
    }

    var mutationID: UUID? {
        for effect in effects {
            if case let .mutate(id, _) = effect { return id }
        }
        return nil
    }

    var mutation: StackDocumentMutation? {
        for effect in effects {
            if case let .mutate(_, mutation) = effect { return mutation }
        }
        return nil
    }
}
