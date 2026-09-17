import Foundation
import XCTest
@testable import SendpointDomain

final class StackDocumentMutationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testSwitchMovesTheCurrentStackAndRejectsUnknownStacks() {
        let initial = StackDocument(
            stacks: filled([Stack(id: firstID), Stack(id: secondID)]),
            currentStackID: firstID
        )

        let switched = applied(.switchStack(stackID: secondID), to: initial)
        XCTAssertEqual(switched.currentStackID, secondID)
        XCTAssertEqual(switched.stacks, initial.stacks)
        XCTAssertEqual(StackDocumentMutations.applying(.switchStack(stackID: secondID), to: switched), .noOp)
        XCTAssertEqual(
            StackDocumentMutations.applying(.switchStack(stackID: UUID()), to: switched),
            .rejected("The stack no longer exists.")
        )
    }

    func testStacksAreNumberedByPlace() {
        let stacks = StackDocument.empty().stacks
        XCTAssertEqual(stacks.count, StackDocument.stackCount)
        XCTAssertEqual(stacks.map { stacks.number(of: $0.id) }, [1, 2, 3, 4, 5])
        XCTAssertEqual(stacks.stack(number: 3), stacks[2])
        XCTAssertNil(stacks.stack(number: 0))
        XCTAssertNil(stacks.stack(number: 6))
        XCTAssertNil(stacks.number(of: UUID()))
    }

    func testStartedAtIsTheEarliestNote() {
        XCTAssertNil(Stack().startedAt)
        let late = Note(subject: .standalone, body: "late", createdAt: now.addingTimeInterval(60))
        let early = Note(subject: .standalone, body: "early", createdAt: now)
        XCTAssertEqual(Stack(notes: [late, early]).startedAt, now)
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
        let stack = Stack(id: firstID, notes: [one, two, three])
        let initial = StackDocument(stacks: filled([stack]), currentStackID: firstID)

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

    func testMovingANoteAcrossStacksAppendsItAndMakesTheDestinationCurrent() {
        let moved = makeNote(id: UUID(), body: "moved")
        let stays = makeNote(id: UUID(), body: "stays")
        let waiting = makeNote(id: UUID(), body: "waiting")
        let initial = StackDocument(
            stacks: filled([Stack(id: firstID, notes: [moved, stays]), Stack(id: secondID, notes: [waiting])]),
            currentStackID: firstID
        )

        let result = applied(.moveNoteToStack(noteID: moved.id, from: firstID, to: secondID), to: initial)
        XCTAssertEqual(result.stacks[0].notes, [stays])
        XCTAssertEqual(result.stacks[1].notes, [waiting, moved])
        XCTAssertEqual(result.currentStackID, secondID)

        XCTAssertEqual(
            StackDocumentMutations.applying(.moveNoteToStack(noteID: moved.id, from: firstID, to: firstID), to: initial),
            .noOp
        )
        XCTAssertEqual(
            StackDocumentMutations.applying(.moveNoteToStack(noteID: moved.id, from: firstID, to: secondID), to: result),
            .rejected("The note no longer exists."),
            "a repeated move finds the note already gone"
        )
        XCTAssertEqual(
            StackDocumentMutations.applying(.moveNoteToStack(noteID: moved.id, from: firstID, to: UUID()), to: initial),
            .rejected("The stack no longer exists.")
        )
    }

    func testClearCanBeUndoneAfterSwitchingStacks() {
        let old = makeNote(id: UUID(), body: "old")
        let first = Stack(id: firstID, notes: [old])
        let second = Stack(id: secondID)
        let initial = StackDocument(stacks: filled([first, second]), currentStackID: firstID)

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
        let first = Stack(id: firstID, notes: [old])
        let initial = StackDocument(stacks: filled([first]), currentStackID: firstID)
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

    func testClearExportedNotesRejectsSnapshotsOlderThanAnyNoteField() {
        let note = makeNote(id: UUID(), body: "original")
        let initial = StackDocument(
            stacks: filled([Stack(id: firstID, notes: [note])]),
            currentStackID: firstID
        )

        var changedBody = note
        changedBody.body = "edited"
        var changedSubject = note
        changedSubject.subject = .selection(quote: "new quote")
        let changedDate = Note(
            id: note.id,
            subject: note.subject,
            body: note.body,
            createdAt: now.addingTimeInterval(1)
        )
        let changedID = Note(subject: note.subject, body: note.body, createdAt: note.createdAt)

        for stale in [changedBody, changedSubject, changedDate, changedID] {
            XCTAssertEqual(
                StackDocumentMutations.applying(
                    .clearExportedNotes(stackID: firstID, notes: [stale]),
                    to: initial
                ),
                .noOp
            )
        }

        let cleared = StackDocumentMutations.applying(
            .clearExportedNotes(stackID: firstID, notes: [note]),
            to: initial
        )
        guard case let .applied(document) = cleared else {
            return XCTFail("Expected the exact export snapshot to clear the note")
        }
        XCTAssertTrue(document.stacks[0].notes.isEmpty)
        XCTAssertEqual(document.lastCleared?.notes, [note])
    }

    func testClearExportedNotesPreservesMixedNoteAndClearedBatchOrdering() {
        let first = makeNote(id: UUID(), body: "first exported")
        let stale = makeNote(id: UUID(), body: "exported before editing")
        var edited = stale
        edited.body = "edited after export"
        let second = makeNote(id: UUID(), body: "second exported")
        let added = makeNote(id: UUID(), body: "added after export")
        let third = makeNote(id: UUID(), body: "third exported")
        let missing = makeNote(id: UUID(), body: "removed after export")
        let initial = StackDocument(
            stacks: filled([Stack(id: firstID, notes: [first, edited, second, added, third])]),
            currentStackID: firstID
        )

        let cleared = applied(
            .clearExportedNotes(stackID: firstID, notes: [third, stale, missing, second, first, second]),
            to: initial
        )

        XCTAssertEqual(cleared.stacks[0].notes, [edited, added])
        XCTAssertEqual(cleared.lastCleared, ClearedBatch(stackID: firstID, notes: [first, second, third]))
        XCTAssertEqual(
            applied(.undoClear, to: cleared).stacks[0].notes,
            [first, second, third, edited, added]
        )
    }

    func testValidationRejectsDuplicateStackNoteAndClearedBatchIDs() {
        let one = makeNote(id: UUID(), body: "one")
        let duplicateStackIDs = StackDocument(
            stacks: filled([Stack(id: firstID), Stack(id: firstID)]),
            currentStackID: firstID
        )
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicateStackIDs)) {
            XCTAssertEqual(
                ($0 as? StackDocumentValidationError)?.message,
                "stack IDs must be unique"
            )
        }

        let duplicateNoteIDs = StackDocument(
            stacks: filled([Stack(id: firstID, notes: [one, one])]),
            currentStackID: firstID
        )
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicateNoteIDs)) {
            XCTAssertEqual(
                ($0 as? StackDocumentValidationError)?.message,
                "note IDs must be unique within a stack"
            )
        }

        let duplicateClearedIDs = StackDocument(
            stacks: filled([Stack(id: firstID)]),
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

    func testValidationRejectsInvalidCurrentStackAndWrongStackCounts() {
        XCTAssertThrowsError(
            try StackDocumentMutations.validate(
                StackDocument(stacks: filled([]), currentStackID: UUID())
            )
        )
        for count in [0, 1, StackDocument.stackCount - 1, StackDocument.stackCount + 1] {
            let stacks = (0..<count).map { _ in Stack() }
            XCTAssertThrowsError(
                try StackDocumentMutations.validate(
                    StackDocument(stacks: stacks, currentStackID: stacks.first?.id ?? UUID())
                ),
                "\(count) stacks"
            )
        }
    }

    private func document() -> StackDocument {
        StackDocument(
            stacks: filled([Stack(id: firstID)]),
            currentStackID: firstID
        )
    }

    private func makeNote(id: UUID, body: String) -> Note {
        Note(
            id: id,
            subject: .standalone,
            body: body,
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
