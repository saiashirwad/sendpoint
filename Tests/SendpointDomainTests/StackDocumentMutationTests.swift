import Foundation
import XCTest
@testable import SendpointDomain

final class StackDocumentMutationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testCreateRenameSwitchAndDeletePreserveDocumentRules() {
        let initial = document()
        let second = Stack(id: secondID, name: "  Second  ", createdAt: now)
        let created = applied(.createStack(second), to: initial)
        XCTAssertEqual(created.stacks.map(\.name), ["First", "Second"])
        XCTAssertEqual(created.currentStackID, secondID)

        let renamed = applied(
            .renameStack(stackID: firstID, name: "  Renamed  "),
            to: created
        )
        XCTAssertEqual(renamed.stacks[0].name, "Renamed")
        let switched = applied(.switchStack(stackID: firstID), to: renamed)
        XCTAssertEqual(switched.currentStackID, firstID)

        let deleted = applied(.deleteStack(stackID: firstID), to: switched)
        XCTAssertEqual(deleted.stacks.map(\.id), [secondID])
        XCTAssertEqual(deleted.currentStackID, secondID)
        XCTAssertEqual(
            StackDocumentMutations.applying(.deleteStack(stackID: secondID), to: deleted),
            .rejected("The last stack cannot be deleted.")
        )
    }

    func testDeletingCurrentSelectsFollowingStackThenPreviousStack() {
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let initial = StackDocument(
            stacks: [
                Stack(id: firstID, name: "First", createdAt: now),
                Stack(id: secondID, name: "Second", createdAt: now),
                Stack(id: thirdID, name: "Third", createdAt: now),
            ],
            currentStackID: secondID
        )

        let deletedMiddle = applied(.deleteStack(stackID: secondID), to: initial)
        XCTAssertEqual(deletedMiddle.stacks.map(\.id), [firstID, thirdID])
        XCTAssertEqual(deletedMiddle.currentStackID, thirdID)

        let deletedLast = applied(.deleteStack(stackID: thirdID), to: deletedMiddle)
        XCTAssertEqual(deletedLast.stacks.map(\.id), [firstID])
        XCTAssertEqual(deletedLast.currentStackID, firstID)
    }

    func testDeletingStackThatOriginatedLastClearDiscardsUndoBatch() {
        let cleared = makeNote(id: UUID(), body: "cleared")
        let initial = StackDocument(
            stacks: [
                Stack(id: firstID, name: "First", createdAt: now),
                Stack(id: secondID, name: "Second", createdAt: now),
            ],
            currentStackID: secondID,
            lastCleared: ClearedBatch(stackID: firstID, notes: [cleared])
        )

        let deleted = applied(.deleteStack(stackID: firstID), to: initial)

        XCTAssertNil(deleted.lastCleared)
        XCTAssertEqual(deleted.currentStackID, secondID)
    }

    func testNamesAreCaseDiacriticAndWidthInsensitive() {
        let initial = document(name: "Résumé")
        let conflictingNames = ["résumé", "RESUME", "ＲＥＳＵＭＥ"]

        for name in conflictingNames {
            XCTAssertEqual(
                StackDocumentMutations.applying(
                    .createStack(Stack(id: UUID(), name: name, createdAt: now)),
                    to: initial
                ),
                .rejected("Stack names must be unique.")
            )
        }

        let second = applied(
            .createStack(Stack(id: secondID, name: "Other", createdAt: now)),
            to: initial
        )
        XCTAssertEqual(
            StackDocumentMutations.applying(
                .renameStack(stackID: secondID, name: " ＲＥＳＵＭＥ "),
                to: second
            ),
            .rejected("Stack names must be unique.")
        )
    }

    func testNoteAddEditMoveAndRemoveUseStableIDs() {
        let one = makeNote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, body: "one")
        let two = makeNote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, body: "two")
        let three = makeNote(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, body: "three")
        var result = applied(.addNote(stackID: firstID, note: one), to: document())
        result = applied(.addNote(stackID: firstID, note: two), to: result)
        result = applied(.addNote(stackID: firstID, note: three), to: result)
        result = applied(
            .updateNoteBody(stackID: firstID, noteID: two.id, body: "changed"),
            to: result
        )
        result = applied(
            .moveNote(stackID: firstID, noteID: one.id, destinationIndex: 2),
            to: result
        )
        XCTAssertEqual(result.stacks[0].notes.map(\.id), [two.id, three.id, one.id])
        XCTAssertEqual(result.stacks[0].notes[0].body, "changed")

        result = applied(.removeNote(stackID: firstID, noteID: three.id), to: result)
        XCTAssertEqual(result.stacks[0].notes.map(\.id), [two.id, one.id])
        XCTAssertEqual(
            StackDocumentMutations.applying(
                .removeNote(stackID: firstID, noteID: three.id),
                to: result
            ),
            .noOp
        )
    }

    func testMoveDestinationIsFinalIndexAndMustReferToAnExistingSlot() {
        let one = makeNote(id: UUID(), body: "one")
        let two = makeNote(id: UUID(), body: "two")
        let three = makeNote(id: UUID(), body: "three")
        let stack = Stack(
            id: firstID,
            name: "First",
            notes: [one, two, three],
            createdAt: now
        )
        let initial = StackDocument(stacks: [stack], currentStackID: firstID)

        let movedDown = applied(
            .moveNote(stackID: firstID, noteID: one.id, destinationIndex: 2),
            to: initial
        )
        XCTAssertEqual(movedDown.stacks[0].notes.map(\.id), [two.id, three.id, one.id])

        let movedUp = applied(
            .moveNote(stackID: firstID, noteID: one.id, destinationIndex: 0),
            to: movedDown
        )
        XCTAssertEqual(movedUp.stacks[0].notes.map(\.id), [one.id, two.id, three.id])
        XCTAssertEqual(
            StackDocumentMutations.applying(
                .moveNote(
                    stackID: firstID,
                    noteID: one.id,
                    destinationIndex: initial.stacks[0].notes.endIndex
                ),
                to: initial
            ),
            .rejected("The destination is outside the stack.")
        )
    }

    func testClearCanBeUndoneAfterSwitchingStacks() {
        let old = makeNote(id: UUID(), body: "old")
        let first = Stack(id: firstID, name: "First", notes: [old], createdAt: now)
        let second = Stack(id: secondID, name: "Second", createdAt: now)
        let initial = StackDocument(stacks: [first, second], currentStackID: firstID)

        let cleared = applied(.clearStack(stackID: firstID), to: initial)
        XCTAssertTrue(cleared.stacks[0].notes.isEmpty)
        let switched = applied(.switchStack(stackID: secondID), to: cleared)
        let restored = applied(.undoClear, to: switched)

        XCTAssertEqual(restored.currentStackID, secondID)
        XCTAssertEqual(restored.stacks[0].notes, [old])
        XCTAssertNil(restored.lastCleared)
    }

    func testUndoPlacesClearedBatchBeforeLaterEntriesAndReplacesDuplicateIDs() {
        let old = makeNote(id: UUID(), body: "old")
        let later = makeNote(id: UUID(), body: "later")
        let first = Stack(id: firstID, name: "First", notes: [old], createdAt: now)
        let initial = StackDocument(stacks: [first], currentStackID: firstID)
        let cleared = applied(.clearStack(stackID: firstID), to: initial)
        let withLater = applied(.addNote(stackID: firstID, note: later), to: cleared)
        var replacement = old
        replacement.body = "duplicate added after clear"
        let withDuplicate = applied(
            .addNote(stackID: firstID, note: replacement),
            to: withLater
        )

        let restored = applied(.undoClear, to: withDuplicate)
        XCTAssertEqual(restored.stacks[0].notes, [old, later])
    }

    func testValidationRejectsDuplicateStackNoteAndClearedBatchIDs() {
        let one = makeNote(id: UUID(), body: "one")
        let duplicateStackIDs = StackDocument(
            stacks: [
                Stack(id: firstID, name: "First", createdAt: now),
                Stack(id: firstID, name: "Second", createdAt: now),
            ],
            currentStackID: firstID
        )
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicateStackIDs)) {
            XCTAssertEqual(
                ($0 as? StackDocumentValidationError)?.message,
                "stack IDs must be unique"
            )
        }

        let duplicateNoteIDs = StackDocument(
            stacks: [
                Stack(id: firstID, name: "First", notes: [one, one], createdAt: now)
            ],
            currentStackID: firstID
        )
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicateNoteIDs)) {
            XCTAssertEqual(
                ($0 as? StackDocumentValidationError)?.message,
                "note IDs must be unique within a stack"
            )
        }

        let duplicateClearedIDs = StackDocument(
            stacks: [Stack(id: firstID, name: "First", createdAt: now)],
            currentStackID: firstID,
            lastCleared: ClearedBatch(stackID: firstID, notes: [one, one])
        )
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicateClearedIDs)) {
            XCTAssertEqual(
                ($0 as? StackDocumentValidationError)?.message,
                "lastCleared note IDs must be unique"
            )
        }
    }

    func testValidationRejectsInvalidCurrentStackAndDuplicateFoldedNames() {
        XCTAssertThrowsError(
            try StackDocumentMutations.validate(
                StackDocument(stacks: [Stack(name: "First")], currentStackID: UUID())
            )
        )
        XCTAssertThrowsError(
            try StackDocumentMutations.validate(
                StackDocument(
                    stacks: [
                        Stack(id: firstID, name: "Café"),
                        Stack(id: secondID, name: "ＣＡＦＥ"),
                    ],
                    currentStackID: firstID
                )
            )
        )
    }

    private func document(name: String = "First") -> StackDocument {
        StackDocument(
            stacks: [Stack(id: firstID, name: name, createdAt: now)],
            currentStackID: firstID
        )
    }

    private func makeNote(id: UUID, body: String) -> Note {
        Note(
            id: id,
            subject: .standalone,
            body: body,
            provenance: Provenance(application: ApplicationIdentity(name: "Tests")),
            createdAt: now
        )
    }

    private func applied(
        _ mutation: StackDocumentMutation,
        to document: StackDocument,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> StackDocument {
        let result = StackDocumentMutations.applying(mutation, to: document)
        guard case let .applied(candidate) = result else {
            XCTFail("Expected applied mutation, got \(result)", file: file, line: line)
            return document
        }
        return candidate
    }
}
