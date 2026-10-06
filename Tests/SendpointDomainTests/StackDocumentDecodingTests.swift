import Foundation
import XCTest
import SendpointDomain

final class StackDocumentDecodingTests: XCTestCase {
    func testFivePermanentSlotsRoundTripWithoutStackIdentityFields() throws {
        let document = StackDocument()
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(StackDocument.self, from: data), document)
        XCTAssertEqual(document.stacks.map(\.id), StackSlot.allCases)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["version"])
        XCTAssertNil(object["stacks"])
        XCTAssertNil(object["currentStackID"])
    }

    func testDecodedMissingSlotIsRejected() throws {
        var object = try encodedObject(StackDocument())
        object.removeValue(forKey: "five")
        XCTAssertThrowsError(try decode(object))
    }

    func testDecodedDuplicateNotesAndInvalidClearedBatchesAreRejected() throws {
        let note = Note(subject: .standalone, body: "one")
        guard case let .applied(document) = StackDocumentMutations.applying(.addNote(stackID: .one, note: note), to: StackDocument()) else {
            return XCTFail("Expected note addition")
        }
        var object = try encodedObject(document)
        let notes = try XCTUnwrap(object["one"] as? [Any])
        object["one"] = notes + notes
        XCTAssertThrowsError(try decode(object))
        object = try encodedObject(document)
        for batch in [
            ["stackID": 1, "notes": []],
            ["stackID": 1, "notes": notes + notes],
            ["stackID": 6, "notes": notes],
        ] as [[String: Any]] {
            object["lastCleared"] = batch
            XCTAssertThrowsError(try decode(object))
        }
    }

    private func encodedObject(_ document: StackDocument) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> StackDocument {
        try JSONDecoder().decode(StackDocument.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
