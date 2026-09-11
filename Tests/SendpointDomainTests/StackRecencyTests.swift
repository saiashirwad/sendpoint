import Foundation
import XCTest
@testable import SendpointDomain

final class StackRecencyTests: XCTestCase {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private var document: StackDocument {
        StackDocument(
            stacks: [
                Stack(id: firstID, name: "First"),
                Stack(id: secondID, name: "Second"),
                Stack(id: thirdID, name: "Third"),
            ],
            currentStackID: firstID
        )
    }

    func testDocumentsWithoutRecencyListByCurrentThenListOrder() {
        XCTAssertEqual(document.recentStackIDs, [])
        XCTAssertEqual(document.stacksByRecency.map(\.id), [firstID, secondID, thirdID])

        var current = document
        current.currentStackID = thirdID
        XCTAssertEqual(current.stacksByRecency.map(\.id), [thirdID, firstID, secondID])
    }

    func testSwitchingRecordsBothTheStackLeftAndTheStackEntered() {
        let switched = applied(.switchStack(stackID: thirdID), to: document)
        XCTAssertEqual(switched.recentStackIDs, [thirdID, firstID])
        XCTAssertEqual(switched.stacksByRecency.map(\.id), [thirdID, firstID, secondID],
            "one step back reaches the stack that was current a moment ago")

        let again = applied(.switchStack(stackID: secondID), to: switched)
        XCTAssertEqual(again.recentStackIDs, [secondID, thirdID, firstID])
        XCTAssertEqual(again.stacksByRecency.map(\.id), [secondID, thirdID, firstID])

        let back = applied(.switchStack(stackID: thirdID), to: again)
        XCTAssertEqual(back.recentStackIDs, [thirdID, secondID, firstID])
    }

    func testCreatingAndAddingNotesTouchTheirStack() {
        let fourthID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let created = applied(.createStack(Stack(id: fourthID, name: "Fourth")), to: document)
        XCTAssertEqual(created.currentStackID, fourthID)
        XCTAssertEqual(created.recentStackIDs, [fourthID])
        XCTAssertEqual(created.stacksByRecency.map(\.id), [fourthID, firstID, secondID, thirdID])

        let note = Note(
            subject: .standalone, body: "note"
        )
        let added = applied(.addNote(stackID: secondID, note: note), to: created)
        XCTAssertEqual(added.recentStackIDs, [secondID, fourthID])
        XCTAssertEqual(added.stacksByRecency.map(\.id), [fourthID, secondID, firstID, thirdID],
            "the current stack always leads; a stack written to comes next")
    }

    func testDeletingRemovesTheStackFromTheRecencyList() {
        let switched = applied(.switchStack(stackID: thirdID), to: document)
        let deleted = applied(.deleteStack(stackID: firstID), to: switched)
        XCTAssertEqual(deleted.recentStackIDs, [thirdID])
        XCTAssertEqual(deleted.stacksByRecency.map(\.id), [thirdID, secondID])
    }

    func testValidationRejectsUnknownAndDuplicateRecentIDs() {
        var unknown = document
        unknown.recentStackIDs = [UUID()]
        XCTAssertThrowsError(try StackDocumentMutations.validate(unknown))

        var duplicate = document
        duplicate.recentStackIDs = [firstID, firstID]
        XCTAssertThrowsError(try StackDocumentMutations.validate(duplicate))

        var fine = document
        fine.recentStackIDs = [secondID, firstID]
        XCTAssertNoThrow(try StackDocumentMutations.validate(fine))
    }

    private func applied(_ mutation: StackDocumentMutation, to document: StackDocument) -> StackDocument {
        guard case let .applied(result) = StackDocumentMutations.applying(mutation, to: document) else {
            XCTFail("expected \(mutation) to apply")
            return document
        }
        return result
    }
}
