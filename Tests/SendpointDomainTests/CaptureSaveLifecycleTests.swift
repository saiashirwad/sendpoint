import Foundation
import XCTest
import SendpointDomain

final class CaptureSaveLifecycleTests: XCTestCase {
    private let identity = CaptureIdentity(sourceStack: .one, createdAt: Date(timeIntervalSince1970: 123))
    private let selection = CapturedSelection(text: "Selection")

    func testDestinationChangesKeepSourceSelectionAndDraftThenFreezeAtSave() throws {
        var state = editing(body: "Keep this draft")
        XCTAssertEqual(state.update(.chooseDestination(identity, .two)), [])
        _ = state.update(.toggleDestinations(identity))
        XCTAssertEqual(state.update(.chooseDestination(identity, .two)), [.switchStack(.two)])
        XCTAssertEqual(state.destination, .choosing(.closed(.two)))
        XCTAssertEqual(state.captured, selection)
        XCTAssertEqual(state.editor, .editing("Keep this draft"))
        XCTAssertEqual(state.identity?.sourceStack, .one)

        let request = try commit(state.update(.save))
        XCTAssertEqual(request.destinationStackID, .two)
        XCTAssertEqual(request.identity, identity)
        XCTAssertEqual(request.selection, selection)
        XCTAssertEqual(request.note.id, identity.noteID)
        XCTAssertEqual(request.note.createdAt, identity.createdAt)
        XCTAssertEqual(request.note.body, "Keep this draft")
        _ = state.update(.stackSelected(.five))
        _ = state.update(.changeNote("late"))
        XCTAssertEqual(state.work, .saving(request))
        XCTAssertEqual(state.destination, .frozen(.two))
    }

    func testSaveBeforeSelectionFreezesBodyAndDestinationUntilItCanCommit() throws {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        _ = state.update(.selectionPending(identity))
        _ = state.update(.changeNote("Quick thought"))
        _ = state.update(.stackSelected(.two))
        _ = state.update(.toggleDestinations(identity))
        XCTAssertEqual(state.update(.save), [])
        guard case .awaitingTextSelection = state.work else { return XCTFail("expected frozen wait") }
        XCTAssertEqual(state.editor, .saving("Quick thought"))
        XCTAssertEqual(state.destination, .frozen(.two))
        _ = state.update(.stackSelected(.five))
        _ = state.update(.changeNote("Edited late"))
        _ = state.update(.chooseDestination(identity, .four))
        let request = try commit(state.update(.selection(identity, selection)))
        XCTAssertEqual(request.note.body, "Quick thought")
        XCTAssertEqual(request.destinationStackID, .two)
        XCTAssertEqual(request.identity, identity)
        XCTAssertEqual(request.selection, selection)
    }

    func testFailedSelectionAlsoReleasesAFrozenTypedSave() throws {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        _ = state.update(.selectionPending(identity))
        _ = state.update(.changeNote("Quick thought"))
        _ = state.update(.save)
        let request = try commit(state.update(.failed(identity, "no focused element")))
        XCTAssertEqual(request.note.subject, .standalone)
        XCTAssertEqual(request.note.body, "Quick thought")
        XCTAssertEqual(request.note.id, identity.noteID)
    }

    func testSaveRetryRetainsExactlyTheSameRequestAndNeverCommitsAgain() throws {
        var state = editing(body: "Draft")
        let request = try commit(state.update(.save))
        XCTAssertEqual(state.update(.saved(request, .commitFailed("disk full"))), [.show(.editor)])
        XCTAssertEqual(state.editor, .failed("Draft", .retryable("Couldn’t save the note: disk full")))
        XCTAssertEqual(state.captured, selection)
        _ = state.update(.stackSelected(.three))
        _ = state.update(.changeNote("late"))
        XCTAssertEqual(state.update(.retry), [.retry])
        XCTAssertEqual(state.work, .saving(request))
        XCTAssertEqual(state.update(.retry), [])
        XCTAssertEqual(state.update(.saved(request, .committed)), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
    }

    func testTerminalOutcomesNeverRetryOrClaimSuccess() throws {
        for (outcome, message) in [
            (StackMutationOutcome.rejected("Already exists"), "Already exists"),
            (.noOp, "The note wasn’t saved."),
            (.cancelled, "The note wasn’t saved."),
        ] {
            var state = editing(body: "Draft")
            let request = try commit(state.update(.save))
            _ = state.update(.saved(request, outcome))
            XCTAssertEqual(state.editor, .failed("Draft", .terminal(message)))
            XCTAssertEqual(state.update(.retry), [])
            XCTAssertEqual(state.update(.dismiss), [.close])
        }
    }

    func testStaleSaveOutcomesCannotCloseOrAlterTheCurrentCapture() throws {
        var state = editing(body: "Draft")
        let request = try commit(state.update(.save))
        let stale = CaptureSaveRequest(identity: identity, selection: selection,
            destinationStackID: .five, note: request.note, input: .typed)
        XCTAssertEqual(state.update(.saved(stale, .committed)), [])
        XCTAssertEqual(state.work, .saving(request))
        _ = state.update(.dismiss)
        _ = state.update(.begin(.typed(CaptureIdentity(sourceStack: .one))))
        let current = state
        XCTAssertEqual(state.update(.saved(request, .committed)), [])
        XCTAssertEqual(state, current)
    }

    func testBlankDraftCannotQueueAndBusyCaptureFocusesOnlyTheEditor() {
        var state = editing(body: " ")
        XCTAssertEqual(state.update(.save), [.beep])
        XCTAssertEqual(state.update(.begin(.typed(identity))), [.focusEditor])
        _ = state.update(.changeNote("Draft"))
        _ = state.update(.save)
        XCTAssertEqual(state.update(.begin(.typed(identity))), [.beep])
        XCTAssertEqual(state.update(.dismiss), [.close])

        var early = CaptureState()
        _ = early.update(.begin(.typed(identity)))
        _ = early.update(.selectionPending(identity))
        XCTAssertEqual(early.update(.save), [.beep])
        XCTAssertEqual(early.editor, .editing(""))
    }

    func testEditorOpensEarlyAndSelectionCatchesUpWithoutReplacingTyping() {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        XCTAssertNil(state.editor)
        XCTAssertEqual(state.update(.selectionPending(identity)), [.show(.editor)])
        XCTAssertNil(state.captured)
        XCTAssertEqual(state.update(.selectionPending(identity)), [])
        _ = state.update(.changeNote("Typed already"))
        XCTAssertEqual(state.update(.selection(identity, selection)), [])
        XCTAssertEqual(state.captured, selection)
        XCTAssertEqual(state.editor, .editing("Typed already"))
        _ = state.update(.selection(identity, CapturedSelection(text: "late different quote")))
        XCTAssertEqual(state.captured, selection)
    }

    func testFailedSelectionOpensAnEmptyEditorOrKeepsTheEarlyDraft() {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        XCTAssertEqual(state.update(.failed(identity, "no focused element")), [.show(.editor)])
        XCTAssertEqual(state.editor, .editing(""))
        XCTAssertEqual(state.captured, CapturedSelection(text: ""))

        var early = CaptureState()
        _ = early.update(.begin(.typed(identity)))
        _ = early.update(.selectionPending(identity))
        _ = early.update(.changeNote("Typed"))
        _ = early.update(.failed(identity, "timed out"))
        XCTAssertEqual(early.editor, .editing("Typed"))
        XCTAssertEqual(early.captured, CapturedSelection(text: ""))
    }

    func testTeardownIsIdempotentAndRejectsLaterEvents() {
        var state = editing(body: "Draft")
        XCTAssertEqual(state.update(.teardown), [.close])
        for event in [CaptureEvent.teardown, .save, .begin(.typed(identity)), .voicePressed,
                      .selection(identity, selection), .voiceModeChanged(.tap)] {
            XCTAssertEqual(state.update(event), [])
        }
        XCTAssertEqual(state.lifecycle, .tornDown)
    }

    private func editing(body: String) -> CaptureState {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        _ = state.update(.selection(identity, selection))
        _ = state.update(.changeNote(body))
        return state
    }

    private func commit(_ effects: [CaptureEffect]) throws -> CaptureSaveRequest {
        guard case let .commit(request)? = effects.first else {
            XCTFail("Expected a commit, got \(effects)")
            throw NSError(domain: "test", code: 1)
        }
        return request
    }
}
