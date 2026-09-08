import Foundation
import XCTest
@testable import SendpointDomain

final class SessionRecencyTests: XCTestCase {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private var document: StoreDocument {
        StoreDocument(
            sessions: [
                Session(id: firstID, name: "First"),
                Session(id: secondID, name: "Second"),
                Session(id: thirdID, name: "Third"),
            ],
            currentSessionID: firstID
        )
    }

    func testDocumentsWithoutRecencyListByCurrentThenListOrder() {
        XCTAssertEqual(document.recentSessionIDs, [])
        XCTAssertEqual(document.sessionsByRecency.map(\.id), [firstID, secondID, thirdID])

        var current = document
        current.currentSessionID = thirdID
        XCTAssertEqual(current.sessionsByRecency.map(\.id), [thirdID, firstID, secondID])
    }

    func testSwitchingRecordsBothTheStackLeftAndTheStackEntered() {
        let switched = applied(.switchSession(sessionID: thirdID), to: document)
        XCTAssertEqual(switched.recentSessionIDs, [thirdID, firstID])
        XCTAssertEqual(switched.sessionsByRecency.map(\.id), [thirdID, firstID, secondID],
            "one step back reaches the stack that was current a moment ago")

        let again = applied(.switchSession(sessionID: secondID), to: switched)
        XCTAssertEqual(again.recentSessionIDs, [secondID, thirdID, firstID])
        XCTAssertEqual(again.sessionsByRecency.map(\.id), [secondID, thirdID, firstID])

        let back = applied(.switchSession(sessionID: thirdID), to: again)
        XCTAssertEqual(back.recentSessionIDs, [thirdID, secondID, firstID])
    }

    func testCreatingAndAddingNotesTouchTheirStack() {
        let fourthID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let created = applied(.createSession(Session(id: fourthID, name: "Fourth")), to: document)
        XCTAssertEqual(created.currentSessionID, fourthID)
        XCTAssertEqual(created.recentSessionIDs, [fourthID])
        XCTAssertEqual(created.sessionsByRecency.map(\.id), [fourthID, firstID, secondID, thirdID])

        let annotation = Annotation(
            subject: .standalone, note: "note",
            provenance: Provenance(application: ApplicationIdentity(name: "Test"))
        )
        let added = applied(.addAnnotation(sessionID: secondID, annotation: annotation), to: created)
        XCTAssertEqual(added.recentSessionIDs, [secondID, fourthID])
        XCTAssertEqual(added.sessionsByRecency.map(\.id), [fourthID, secondID, firstID, thirdID],
            "the current stack always leads; a stack written to comes next")
    }

    func testDeletingRemovesTheStackFromTheRecencyList() {
        let switched = applied(.switchSession(sessionID: thirdID), to: document)
        let deleted = applied(.deleteSession(sessionID: firstID), to: switched)
        XCTAssertEqual(deleted.recentSessionIDs, [thirdID])
        XCTAssertEqual(deleted.sessionsByRecency.map(\.id), [thirdID, secondID])
    }

    func testValidationRejectsUnknownAndDuplicateRecentIDs() {
        var unknown = document
        unknown.recentSessionIDs = [UUID()]
        XCTAssertThrowsError(try SessionDocumentMutations.validate(unknown))

        var duplicate = document
        duplicate.recentSessionIDs = [firstID, firstID]
        XCTAssertThrowsError(try SessionDocumentMutations.validate(duplicate))

        var fine = document
        fine.recentSessionIDs = [secondID, firstID]
        XCTAssertNoThrow(try SessionDocumentMutations.validate(fine))
    }

    func testOlderJSONWithoutTheFieldDecodesAndRoundTrips() throws {
        let json = """
        {"version":1,"currentSessionID":"\(firstID.uuidString)","sessions":[{"id":"\(firstID.uuidString)","name":"First","entries":[],"createdAt":"2026-01-01T00:00:00Z"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoreDocument.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.recentSessionIDs, [])
        XCTAssertNoThrow(try SessionDocumentMutations.validate(decoded))

        var touched = decoded
        touched.recentSessionIDs = [firstID]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let again = try decoder.decode(StoreDocument.self, from: try encoder.encode(touched))
        XCTAssertEqual(again, touched)
    }

    private func applied(_ mutation: SessionDocumentMutation, to document: StoreDocument) -> StoreDocument {
        guard case let .applied(result) = SessionDocumentMutations.applying(mutation, to: document) else {
            XCTFail("expected \(mutation) to apply")
            return document
        }
        return result
    }
}
