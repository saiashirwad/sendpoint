import Foundation
import XCTest
import SendpointDomain

final class LatestNoteStateTests: XCTestCase {
    private let session = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let stackID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    private var draft: LatestNoteDraft {
        LatestNoteDraft(
            sessionID: session,
            stackID: stackID,
            stackName: "Stack 1",
            original: Note(subject: .standalone, body: "Original", createdAt: Date(timeIntervalSince1970: 10)),
            text: "Edited"
        )
    }

    func testStaleSaveDoesNothing() {
        let draft = draft
        var saving = LatestNoteState.saving(draft)
        XCTAssertEqual(saving.update(.saved(UUID(), .committed)), [])
        XCTAssertEqual(saving, .saving(draft))

        var failed = LatestNoteState.failed(draft, "disk", pending: true)
        XCTAssertEqual(failed.update(.saved(UUID(), .committed)), [])
        XCTAssertEqual(failed, .failed(draft, "disk", pending: true))

        var editing = LatestNoteState.editing(draft)
        XCTAssertEqual(editing.update(.saved(draft.sessionID, .committed)), [])
        XCTAssertEqual(editing, .editing(draft))

        XCTAssertEqual(saving.update(.saved(draft.sessionID, .committed)), [.close])
        XCTAssertEqual(saving, .closed)
    }

    func testDiscardWhileEditingDoesNothing() {
        let draft = draft
        var editing = LatestNoteState.editing(draft)
        XCTAssertEqual(editing.update(.discard), [])
        XCTAssertEqual(editing.update(.keepEditing), [])
        XCTAssertEqual(editing, .editing(draft))

        var saving = LatestNoteState.saving(draft)
        XCTAssertEqual(saving.update(.discard), [])
        XCTAssertEqual(saving, .saving(draft))

        var confirming = LatestNoteState.confirmingDiscard(draft)
        XCTAssertEqual(confirming.update(.discard), [.close])
        XCTAssertEqual(confirming, .closed)
    }

    func testTeardownIgnoresLaterEvents() {
        var state = LatestNoteState.editing(draft)
        XCTAssertEqual(state.update(.teardown), [.close])
        XCTAssertEqual(state, .tornDown)
        XCTAssertEqual(state.update(.teardown), [])
        XCTAssertEqual(state.update(.open), [])
        XCTAssertEqual(state.update(.discard), [])
        XCTAssertEqual(state.update(.saved(session, .committed)), [])
        XCTAssertEqual(state, .tornDown)
    }
}
