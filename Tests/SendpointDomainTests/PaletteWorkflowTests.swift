import Foundation
import XCTest
import SendpointDomain

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
            Stack(id: firstStackID, notes: [
                Note(id: firstNoteID, subject: .standalone, body: "One"),
                Note(id: secondNoteID, subject: .selection(quote: "quote"), body: "Two"),
                Note(id: thirdNoteID, subject: .standalone, body: "Three"),
            ]),
            Stack(id: secondStackID, notes: [
                Note(id: fourthNoteID, subject: .standalone, body: "Four"),
            ]),
        ]
    }

    func testOpenShowsTheCurrentStackAtItsNewestNote() {
        var harness = makeHarness()
        harness.send(.open)

        XCTAssertEqual(harness.projection.shownStack?.id, firstStackID)
        XCTAssertEqual(harness.state.shownStackID, firstStackID)
        XCTAssertEqual(harness.state.noteState.highlight, thirdNoteID)
        XCTAssertEqual(harness.state.focusRequest.field, .search)
    }

    func testNothingReopensAfterTeardown() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.teardown)
        XCTAssertEqual(harness.closeCount, 1)

        harness.send(.open)
        harness.send(.teardown)
        XCTAssertEqual(harness.state.lifecycle, .tornDown)
        XCTAssertTrue(harness.effects.isEmpty, "teardown is idempotent")
    }

    func testArrowsAreConsumedAndMoveNotesOnce() {
        var harness = makeHarness()
        harness.send(.open)

        XCTAssertTrue(harness.send(.key(.up, textHasSelection: false)))
        XCTAssertEqual(harness.state.noteState.highlight, secondNoteID)
        XCTAssertTrue(harness.send(.key(.down, textHasSelection: false)))
        XCTAssertEqual(harness.state.noteState.highlight, thirdNoteID)
        XCTAssertTrue(harness.send(.key(.down, textHasSelection: false)))
        XCTAssertEqual(harness.state.noteState.highlight, firstNoteID, "the highlight wraps")
    }

    func testTheNoteEditorDeclinesArrowsWithoutChangingDraftOrHighlight() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.editNote(secondNoteID)))
        harness.send(.editText("Draft"))
        let draft = harness.state.inlineEdit
        XCTAssertEqual(draft, PaletteEdit(stackID: firstStackID, noteID: secondNoteID, text: "Draft"))

        for key: PaletteKey in [.up, .down, .optionUp, .commandDigit(2)] {
            XCTAssertFalse(harness.send(.key(key, textHasSelection: false)))
            XCTAssertEqual(harness.state.inlineEdit, draft)
            XCTAssertEqual(harness.state.noteState.highlight, secondNoteID)
            XCTAssertTrue(harness.effects.isEmpty)
        }
    }

    func testOverlayConsumesVerticalArrowsWithoutMovingTheNoteHighlight() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.toggleOverlay(.actions))
        let note = harness.state.noteState.highlight

        XCTAssertTrue(harness.send(.key(.down, textHasSelection: false)))
        XCTAssertEqual(harness.state.overlayHighlight, 1)
        XCTAssertTrue(harness.send(.key(.up, textHasSelection: false)))
        XCTAssertEqual(harness.state.overlayHighlight, 0)
        XCTAssertEqual(harness.state.noteState.highlight, note)
    }

    func testCommandDigitsAndTheStripSelectStacksByNumber() {
        var harness = makeHarness()
        harness.send(.open)

        harness.send(.key(.commandDigit(2), textHasSelection: false))
        XCTAssertEqual(harness.mutation, .switchStack(stackID: secondStackID))

        harness = makeHarness()
        harness.send(.open)
        harness.send(.selectStack(1))
        XCTAssertEqual(harness.mutation, .switchStack(stackID: firstStackID),
            "a queued switch elsewhere may be pending, so the store decides what is a no-op")

        harness = makeHarness()
        harness.send(.open)
        harness.send(.key(.commandDigit(StackDocument.stackCount + 1), textHasSelection: false))
        XCTAssertNil(harness.mutation)
        XCTAssertEqual(harness.beepCount, 1)
    }

    func testTheViewerFollowsAStackSwitchMadeElsewhere() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.query("tw"))
        XCTAssertEqual(harness.projection.noteListing.ids, [secondNoteID])

        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.documentChanged)

        XCTAssertEqual(harness.projection.shownStack?.id, secondStackID)
        XCTAssertEqual(harness.state.shownStackID, secondStackID)
        XCTAssertEqual(harness.state.query, "", "a search belongs to the stack it was typed in")
        XCTAssertEqual(harness.state.noteState.highlight, fourthNoteID)
        XCTAssertTrue(harness.effects.isEmpty)
    }

    func testAStackSwitchMadeElsewhereClosesAnOpenOverlay() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.toggleOverlay(.actions))
        XCTAssertEqual(harness.state.focusRequest.field, .overlay)

        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.documentChanged)

        XCTAssertNil(harness.state.overlay, "the search field is disabled under an overlay, so it cannot take focus")
        XCTAssertEqual(harness.state.focusRequest.field, .search)
    }

    func testADraftIsSavedToTheStackItBeganInWhenTheCurrentStackChanges() throws {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.editNote(secondNoteID)))
        harness.send(.editText("Finished elsewhere"))

        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.documentChanged)

        XCTAssertEqual(
            harness.mutation,
            .updateNoteBody(stackID: firstStackID, noteID: secondNoteID, body: "Finished elsewhere")
        )
        XCTAssertEqual(harness.projection.shownStack?.id, secondStackID)
        XCTAssertEqual(harness.state.noteState.highlight, fourthNoteID)

        harness.send(.mutationResult(try XCTUnwrap(harness.mutationID), .committed))
        XCTAssertNil(harness.state.inlineEdit)
        XCTAssertFalse(harness.state.isBusy)
        XCTAssertEqual(harness.projection.shownStack?.id, secondStackID)
    }

    func testEscapeClosesAViewerStuckOnARetryableFailure() throws {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.deleteNote(secondNoteID)))
        let id = try XCTUnwrap(harness.mutationID)
        harness.send(.mutationResult(id, .commitFailed("disk full")))

        XCTAssertTrue(harness.send(.key(.escape, textHasSelection: false)))
        XCTAssertEqual(harness.state.lifecycle, .closed, "the store keeps the pending change, so nothing is lost")
        XCTAssertEqual(harness.closeCount, 1)
    }

    func testAFlashDoesNotOutliveTheViewerItWasShownIn() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.flash("Copied 3 notes"))
        XCTAssertNotNil(harness.state.flash)

        harness.send(.close)
        harness.send(.open)
        XCTAssertNil(harness.state.flash)
    }

    func testAFailedSaveForAnotherStackIsNamedByItsStack() throws {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.editNote(secondNoteID)))
        harness.send(.editText("Draft"))
        harness.send(.commitEdit)
        let id = try XCTUnwrap(harness.mutationID)

        harness.send(.mutationResult(id, .commitFailed("disk full")))
        XCTAssertEqual(harness.projection.problem, "disk full")

        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.documentChanged)
        XCTAssertEqual(harness.projection.problem, "Stack 1: disk full")
        XCTAssertEqual(harness.state.inlineEdit?.text, "Draft", "the draft waits for a retry")

        harness.send(.retry)
        harness.send(.mutationResult(id, .committed))
        XCTAssertNil(harness.projection.problem)
        XCTAssertNil(harness.state.inlineEdit)
    }

    func testAResultForAnotherOperationIsIgnored() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.clearStack))
        XCTAssertTrue(harness.state.isBusy)

        harness.send(.mutationResult(UUID(), .committed))
        XCTAssertTrue(harness.state.isBusy)
    }

    func testStackActionsAlwaysMeanTheCurrentStack() {
        var harness = makeHarness()
        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.open)

        harness.send(.key(.shiftCommandDelete, textHasSelection: false))
        XCTAssertEqual(harness.mutation, .clearStack(stackID: secondStackID))

        harness = makeHarness()
        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID)
        harness.send(.open)
        harness.send(.key(.shiftCommand("c"), textHasSelection: false))
        XCTAssertEqual(harness.copiedStackID, secondStackID)

        harness.send(.key(.commandDelete, textHasSelection: false))
        XCTAssertEqual(harness.mutation, .removeNote(stackID: secondStackID, noteID: fourthNoteID))
    }

    func testTheHighlightedNoteMovesToAnotherStackAndTheViewerFollowsIt() throws {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.key(.up, textHasSelection: false))
        XCTAssertEqual(harness.state.noteState.highlight, secondNoteID)

        XCTAssertTrue(harness.send(.key(.moveToStack(2), textHasSelection: false)))
        XCTAssertEqual(
            harness.mutation, .moveNoteToStack(noteID: secondNoteID, from: firstStackID, to: secondStackID)
        )
        let id = try XCTUnwrap(harness.mutationID)

        guard case let .applied(document) = StackDocumentMutations.applying(
            try XCTUnwrap(harness.mutation),
            to: StackDocument(stacks: harness.context.stacks, currentStackID: firstStackID)
        ) else { return XCTFail("the move applies") }
        harness.context = makeContext(stacks: Array(document.stacks.prefix(2)), currentStackID: document.currentStackID)
        harness.send(.documentChanged)
        harness.send(.mutationResult(id, .committed))

        XCTAssertEqual(harness.projection.shownStack?.id, secondStackID)
        XCTAssertEqual(harness.state.noteState.highlight, secondNoteID, "the moved note is the newest there")
        XCTAssertEqual(harness.state.flash?.text, "Moved to Stack 2")
        XCTAssertEqual(harness.flashClearGenerations, [1])
        XCTAssertFalse(harness.state.isBusy)
    }

    func testMovingNeedsAHighlightedNoteAndAnotherStack() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.key(.moveToStack(1), textHasSelection: false))
        XCTAssertNil(harness.mutation, "already in this stack")
        XCTAssertEqual(harness.beepCount, 1)

        harness.context = makeContext(stacks: stacks, currentStackID: paddedStacks(stacks)[2].id)
        harness.send(.documentChanged)
        harness.send(.key(.moveToStack(1), textHasSelection: false))
        XCTAssertNil(harness.mutation, "nothing is highlighted in an empty stack")
        XCTAssertEqual(harness.beepCount, 1)
    }

    func testTheMoveKeyBelongsToTheTextFieldWhileEditing() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.perform(.editNote(secondNoteID)))

        XCTAssertFalse(harness.send(.key(.moveToStack(2), textHasSelection: false)))
        XCTAssertNil(harness.mutation)
        XCTAssertNotNil(harness.state.inlineEdit)
    }

    func testMovesAreListedForEveryOtherStackWithTheirKeys() {
        var harness = makeHarness()
        harness.context = makeContext(stacks: stacks, moveShortcuts: [2: "⌥⇧J", 3: "⌥⇧K"])
        harness.send(.open)

        let moves = harness.projection.actionItems.filter {
            if case .moveNoteToStack = $0.action { return true }
            return false
        }
        XCTAssertEqual(moves.map(\.title), ["Move to Stack 2", "Move to Stack 3", "Move to Stack 4", "Move to Stack 5"])
        XCTAssertEqual(moves.map(\.keys), ["⌥⇧J", "⌥⇧K", "", ""])
        XCTAssertEqual(moves.first?.action, .moveNoteToStack(thirdNoteID, 2))
    }

    func testUndoIsOfferedOnlyForTheCurrentStack() {
        let cleared = ClearedBatch(stackID: firstStackID, notes: [Note(subject: .standalone, body: "Gone")])
        var harness = makeHarness()
        harness.context = makeContext(stacks: stacks, currentStackID: secondStackID, lastCleared: cleared)
        harness.send(.open)

        XCTAssertNil(harness.projection.undo)
        XCTAssertFalse(harness.projection.showsUndoInFooter)
        XCTAssertFalse(harness.projection.actionItems.contains { $0.action == .undoClear })
        harness.send(.key(.command("z"), textHasSelection: false))
        XCTAssertNil(harness.mutation)
        XCTAssertEqual(harness.beepCount, 1)

        harness.context = makeContext(stacks: stacks, currentStackID: firstStackID, lastCleared: cleared)
        harness.send(.documentChanged)
        XCTAssertEqual(harness.projection.undo?.stackID, firstStackID)
        XCTAssertTrue(harness.projection.showsUndoInFooter)
        harness.send(.key(.command("z"), textHasSelection: false))
        XCTAssertEqual(harness.mutation, .undoClear)
    }

    func testAClearedEmptyStackOffersUndoInItsEmptyState() {
        let cleared = ClearedBatch(stackID: firstStackID, notes: [Note(subject: .standalone, body: "Gone")])
        var harness = makeHarness()
        harness.context = makeContext(stacks: [Stack(id: firstStackID)], lastCleared: cleared)
        harness.send(.open)

        XCTAssertNotNil(harness.projection.undo)
        XCTAssertFalse(harness.projection.showsUndoInFooter)
    }

    func testAnEmptyStackOffersNothingToCopyOrClear() {
        var harness = makeHarness()
        harness.context = makeContext(stacks: stacks, currentStackID: paddedStacks(stacks)[2].id)
        harness.send(.open)

        XCTAssertEqual(harness.projection.actionItems.map(\.action), [.chooseTemplate])
        harness.send(.key(.shiftCommandDelete, textHasSelection: false))
        XCTAssertNil(harness.mutation)
        XCTAssertEqual(harness.beepCount, 1)
        XCTAssertTrue(harness.send(.key(.activate, textHasSelection: false)))
        XCTAssertEqual(harness.beepCount, 1)
        XCTAssertNil(harness.state.inlineEdit)
    }

    func testEscapeClearsTheQueryBeforeClosing() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.query("one"))

        harness.send(.key(.escape, textHasSelection: false))
        XCTAssertEqual(harness.state.query, "")
        XCTAssertEqual(harness.state.lifecycle, .open)

        harness.send(.key(.escape, textHasSelection: false))
        XCTAssertEqual(harness.state.lifecycle, .closed)
        XCTAssertEqual(harness.closeCount, 1)
    }

    func testOverlayHighlightWithCurrentIndexIsANoOp() {
        var harness = makeHarness()
        harness.send(.open)
        harness.send(.toggleOverlay(.actions))
        XCTAssertEqual(harness.state.overlayHighlight, 0)

        harness.send(.overlayHighlight(2))
        XCTAssertEqual(harness.state.overlayHighlight, 2)

        let generation = harness.state.focusRequest.generation
        harness.send(.overlayHighlight(2))
        XCTAssertEqual(harness.state.overlayHighlight, 2)
        XCTAssertTrue(harness.effects.isEmpty, "re-highlighting the current index must not produce effects")
        XCTAssertEqual(harness.state.focusRequest.generation, generation,
            "re-highlighting the current index must not touch state")
    }

    // MARK: - Harness

    private func makeHarness() -> Harness {
        Harness(state: PaletteWorkflow(), context: makeContext(stacks: stacks))
    }

    private let padding = (0..<StackDocument.stackCount).map { _ in Stack() }

    private func paddedStacks(_ leading: [Stack]) -> [Stack] {
        leading + padding.dropFirst(leading.count)
    }

    private func makeContext(
        stacks: [Stack], currentStackID: UUID? = nil, lastCleared: ClearedBatch? = nil,
        moveShortcuts: [Int: String] = [:]
    ) -> PaletteContext {
        PaletteContext(
            stacks: paddedStacks(stacks),
            currentStackID: currentStackID ?? stacks[0].id,
            lastCleared: lastCleared,
            templates: [.plain],
            activeTemplate: .plain,
            moveShortcuts: moveShortcuts
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
        var update = PaletteUpdate(state: state, context: context, operationID: UUID())
        let handled = update.update(event)
        state = update.state
        effects = update.effects
        return handled
    }

    var projection: PaletteProjection { PaletteProjection(state: state, context: context) }

    var beepCount: Int {
        effects.filter { if case .beep = $0 { return true } else { return false } }.count
    }

    var closeCount: Int {
        effects.filter { if case .close = $0 { return true } else { return false } }.count
    }

    var flashClearGenerations: [Int] {
        effects.compactMap { if case let .clearFlashLater(generation) = $0 { return generation } else { return nil } }
    }

    var copiedStackID: UUID? {
        for effect in effects {
            if case let .copyStack(id) = effect { return id }
        }
        return nil
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
