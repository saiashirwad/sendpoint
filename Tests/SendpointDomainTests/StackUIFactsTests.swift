import Foundation
import XCTest
import SendpointDomain

final class StackUITests: XCTestCase {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testStacksAreKnownByNumberWithTheirCountAndAge() {
        let early = Note(subject: .standalone, body: "Early", createdAt: Date(timeIntervalSince1970: 100))
        let late = Note(subject: .standalone, body: "Late", createdAt: Date(timeIntervalSince1970: 200))
        let facts = StackUIFacts(
            stacks: filled([Stack(id: firstID), Stack(id: secondID, notes: [late, early])]),
            currentStackID: secondID,
            lastCleared: nil
        )

        XCTAssertEqual(facts.stacks.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(facts.stacks.map(\.name).prefix(2), ["Stack 1", "Stack 2"])
        XCTAssertEqual(facts.current?.number, 2)
        XCTAssertEqual(facts.current?.countLabel, "2 notes")
        XCTAssertEqual(facts.current?.startedAt, early.createdAt)
        XCTAssertEqual(facts.stack(number: 1)?.id, firstID)
        XCTAssertTrue(facts.stack(number: 1)?.isEmpty == true)
        XCTAssertNil(facts.stack(number: 1)?.startedAt)
        XCTAssertNil(facts.stack(number: 6))
        XCTAssertNil(facts.undo)
    }

    func testUndoFactsIdentifyANoncurrentSourceStack() {
        let cleared = [makeNote("One"), makeNote("Two")]
        let facts = StackUIFacts(
            stacks: filled([Stack(id: firstID), Stack(id: secondID)]),
            currentStackID: secondID,
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )

        XCTAssertEqual(facts.undo?.stackID, firstID)
        XCTAssertEqual(facts.undo?.title, "Undo Clear in Stack 1 (2)")
        XCTAssertEqual(facts.undo?.notification, "Cleared 2 notes in Stack 1")

        let current = StackUIFacts(
            stacks: filled([Stack(id: firstID), Stack(id: secondID)]),
            currentStackID: firstID,
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )
        XCTAssertEqual(current.undo?.title, "Undo Clear (2)")
    }

    private func makeNote(_ body: String) -> Note {
        Note(
            subject: .standalone,
            body: body
        )
    }
}
