import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

final class StackUITests: XCTestCase {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testSingleStackCannotBeDeleted() {
        let facts = StackUIFacts(
            stacks: [Stack(id: firstID, name: "Only")],
            currentStackID: firstID,
            lastCleared: nil
        )

        XCTAssertFalse(facts.canDelete)

        let cleared = [makeNote("Cleared")]
        let deletion = StackDeletionFacts(
            stackID: firstID,
            stacks: [
                Stack(id: firstID, name: "Cleared"),
                Stack(id: secondID, name: "Other"),
            ],
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )
        XCTAssertTrue(deletion.requiresConfirmation)
        XCTAssertTrue(deletion.includesUndoBatch)
        XCTAssertEqual(deletion.noteCount, 1)
    }

    func testUndoFactsIdentifyANoncurrentSourceStack() {
        let cleared = [makeNote("One"), makeNote("Two")]
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: secondID,
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )

        XCTAssertEqual(facts.undo?.stackID, firstID)
        XCTAssertEqual(facts.undo?.title, "Undo Clear in Reading (2)")
        XCTAssertEqual(facts.undo?.notification, "Cleared 2 notes in Reading")
    }

    func testNameDraftTrimsAndRejectsBlankOrFoldedDuplicates() {
        let stacks = [Stack(id: firstID, name: "Résumé")]

        XCTAssertEqual(
            StackNameDraft(text: "  New Notes  ", excludedStackID: nil)
                .validation(stacks: stacks),
            .valid("New Notes")
        )
        XCTAssertEqual(
            StackNameDraft(text: " \n ", excludedStackID: nil)
                .validation(stacks: stacks),
            .invalid("Enter a stack name.")
        )
        for duplicate in ["résumé", "RESUME", "ＲＥＳＵＭＥ"] {
            XCTAssertEqual(
                StackNameDraft(text: duplicate, excludedStackID: nil)
                    .validation(stacks: stacks),
                .invalid("A stack with that name already exists.")
            )
        }
    }

    func testRenameDraftExcludesCapturedStackButNotOtherStacks() {
        let stacks = [
            Stack(id: firstID, name: "Reading"),
            Stack(id: secondID, name: "Writing"),
        ]

        XCTAssertEqual(
            StackNameDraft(text: " reading ", excludedStackID: firstID)
                .validation(stacks: stacks),
            .valid("reading")
        )
        XCTAssertEqual(
            StackNameDraft(text: "WRITING", excludedStackID: firstID)
                .validation(stacks: stacks),
            .invalid("A stack with that name already exists.")
        )
    }

    func testQuickSwitchStateKeepsExplicitSelectionAndFallsBackAfterDeletion() {
        let both = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )
        var state = QuickSwitchState()
        state.synchronize(with: both)
        XCTAssertEqual(state.selectedStackID, firstID)
        XCTAssertEqual(state.choose(secondID, from: both), secondID)
        XCTAssertEqual(state.selectedStackID, secondID)
        XCTAssertNil(state.choose(UUID(), from: both))
        XCTAssertEqual(state.selectedStackID, secondID)
        state.selectCurrent(from: both)
        XCTAssertEqual(state.selectedStackID, firstID)
        _ = state.choose(secondID, from: both)

        let afterDeletion = StackUIFacts(
            stacks: [Stack(id: firstID, name: "Reading")],
            currentStackID: firstID,
            lastCleared: nil
        )
        state.synchronize(with: afterDeletion)
        XCTAssertEqual(state.selectedStackID, firstID)
    }

    private func makeNote(_ body: String) -> Note {
        Note(
            subject: .standalone,
            body: body
        )
    }
}

extension StackUITests {
    func testQuickSwitchListingFiltersAndOffersCreation() {
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )

        let everything = QuickSwitchListing(facts: facts, query: "   ")
        XCTAssertEqual(everything.stacks.map(\.id), [firstID, secondID])
        XCTAssertNil(everything.creatableName)

        let partial = QuickSwitchListing(facts: facts, query: "ITI")
        XCTAssertEqual(partial.stacks.map(\.id), [secondID])
        XCTAssertEqual(partial.creatableName, "ITI")
        XCTAssertEqual(partial.rows, [.stack(secondID), .create("ITI")])

        let existing = QuickSwitchListing(facts: facts, query: " reading ")
        XCTAssertEqual(existing.stacks.map(\.id), [firstID])
        XCTAssertNil(existing.creatableName, "an existing name is not offered for creation")

        let none = QuickSwitchListing(facts: facts, query: "zzz")
        XCTAssertTrue(none.stacks.isEmpty)
        XCTAssertEqual(none.rows, [.create("zzz")])
    }

    func testQuickSwitchStateMovesThroughRowsAndConfinesToListing() {
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )
        let rows: [QuickSwitchRow] = [.stack(firstID), .stack(secondID), .create("New")]

        var state = QuickSwitchState()
        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .stack(firstID))

        state.move(by: -1, in: rows)
        XCTAssertEqual(state.highlight, .create("New"), "moving up from the top wraps")
        XCTAssertNil(state.selectedStackID)

        state.move(by: 1, in: rows)
        XCTAssertEqual(state.highlight, .stack(firstID), "moving down from the bottom wraps")

        state.move(by: 1, in: rows)
        XCTAssertEqual(state.selectedStackID, secondID)

        state.confine(to: [.stack(secondID)], preferring: firstID)
        XCTAssertEqual(state.highlight, .stack(secondID), "a still-listed highlight is kept")

        state.confine(to: [.create("Wri")], preferring: firstID)
        XCTAssertEqual(state.highlight, .create("Wri"), "otherwise the first listed row wins")

        state.confine(to: [.stack(secondID), .stack(firstID)], preferring: firstID)
        XCTAssertEqual(state.highlight, .stack(firstID), "the current stack is preferred when listed")

        state.move(by: 1, in: [])
        XCTAssertEqual(state.highlight, .stack(firstID), "an empty listing leaves the highlight alone")

        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .stack(firstID))
        state.highlight(.create("Draft"))
        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .create("Draft"), "stack changes keep a create highlight")
    }
}
