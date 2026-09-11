import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

/// The save half of the capture reducer: a typed note becomes one exact
/// request, and only that request's outcome can move the capture on.
final class CaptureSaveLifecycleTests: XCTestCase {
    private let context = NoteCaptureContext(
        stackID: UUID(), createdAt: Date(timeIntervalSince1970: 123)
    )
    private let selection = CapturedSelection(
        text: "Selection", appName: "Reader", appBundleID: "com.example.reader",
        processIdentifier: 42, screenRect: nil
    )

    func testSaveFreezesTheNoteAndRetryReusesTheExactRequest() throws {
        var state = try editing(body: "Keep this draft")
        let target = try XCTUnwrap(state.session?.target)

        let effects = state.update(.save)
        let request = CaptureSaveRequest(
            target: target, destinationStackID: context.stackID,
            note: try XCTUnwrap(target.note(body: "Keep this draft"))
        )
        XCTAssertEqual(effects, [.save(request)])
        XCTAssertEqual(state.update(.changeNote("A late edit")), [])
        XCTAssertEqual(state.session?.phase, .saving(request))

        XCTAssertEqual(state.update(.prepared(request, request.note)), [.commit(request)])
        XCTAssertEqual(
            state.update(.saved(request, .commitFailed("disk full"), destinationExists: true)),
            [.show(.editor)]
        )
        XCTAssertEqual(state.session?.phase, .saveFailed(
            request, message: "Couldn’t save the note: disk full", retryable: true, targetMissing: false
        ))
        XCTAssertEqual(state.update(.retarget(UUID())), [], "a retryable failure keeps its destination")

        XCTAssertEqual(state.update(.retry), [.retry])
        XCTAssertEqual(state.session?.phase, .saving(request))
        XCTAssertEqual(state.update(.saved(request, .committed, destinationExists: true)), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
    }

    func testMissingDestinationKeepsTheNoteForAnExplicitRetarget() throws {
        var (state, request) = try saving()
        XCTAssertEqual(
            state.update(.saved(request, .rejected("The target stack no longer exists."), destinationExists: false)),
            [.show(.editor)]
        )
        XCTAssertEqual(state.session?.phase, .saveFailed(
            request, message: "That stack was deleted.", retryable: false, targetMissing: true
        ))
        XCTAssertEqual(state.update(.retry), [])

        let destination = UUID()
        let retargeted = CaptureSaveRequest(
            target: request.target, destinationStackID: destination, note: request.note
        )
        XCTAssertEqual(state.update(.retarget(destination)), [.abandon(request.target), .save(retargeted)])
        XCTAssertEqual(state.session?.phase, .saving(retargeted))
        XCTAssertEqual(state.update(.prepared(retargeted, retargeted.note)), [.commit(retargeted)])
        XCTAssertEqual(state.update(.saved(retargeted, .committed, destinationExists: true)), [.close])
    }

    func testRejectedExistingDestinationCannotRetargetAndDismissAbandonsProvenance() throws {
        var (state, request) = try saving()
        _ = state.update(.saved(request, .rejected("The note already exists."), destinationExists: true))
        XCTAssertEqual(state.session?.phase, .saveFailed(
            request, message: "The note already exists.", retryable: false, targetMissing: false
        ))
        XCTAssertEqual(state.update(.retarget(UUID())), [])
        XCTAssertEqual(state.update(.dismiss), [.abandon(request.target), .close])
    }

    func testStaleOutcomesAreIgnored() throws {
        var (state, request) = try saving()
        let otherNote = Note(
            subject: .standalone, body: "Other", provenance: request.note.provenance
        )
        for stale in [
            CaptureSaveRequest(target: request.target, destinationStackID: UUID(), note: request.note),
            CaptureSaveRequest(target: request.target, destinationStackID: request.destinationStackID,
                note: otherNote),
        ] {
            XCTAssertEqual(state.update(.prepared(stale, stale.note)), [])
            XCTAssertEqual(state.update(.saved(stale, .committed, destinationExists: true)), [])
            XCTAssertEqual(state.session?.phase, .saving(request))
        }
        XCTAssertEqual(state.update(.prepared(request, otherNote)), [], "the prepared note must keep its id")
    }

    func testNoOpAndCancellationNeverClaimSuccess() throws {
        for outcome in [StackMutationOutcome.noOp, .cancelled] {
            var (state, request) = try saving()
            XCTAssertEqual(state.update(.saved(request, outcome, destinationExists: true)), [.show(.editor)])
            XCTAssertEqual(state.session?.phase, .saveFailed(
                request, message: "The note wasn’t saved.", retryable: false, targetMissing: false
            ))
            XCTAssertEqual(state.update(.retarget(UUID())), [])
            XCTAssertEqual(state.update(.retry), [])
        }
    }

    func testDismissAbandonsOnlyUnsavedWorkAndLateOutcomesAreDropped() throws {
        var editing = try editing(body: "")
        let target = try XCTUnwrap(editing.session?.target)
        XCTAssertEqual(editing.update(.save), [.beep], "a blank note cannot be saved")
        XCTAssertEqual(editing.update(.begin(.text, context)), [.focusEditor])
        XCTAssertEqual(editing.update(.dismiss), [.abandon(target), .close])

        var (queued, request) = try saving()
        XCTAssertEqual(queued.update(.begin(.text, context)), [.beep])
        XCTAssertEqual(queued.update(.dismiss), [.close], "a queued save keeps its provenance work")
        XCTAssertEqual(queued.update(.saved(request, .committed, destinationExists: true)), [])
        XCTAssertEqual(queued.lifecycle, .idle)

        var (failed, failedRequest) = try saving()
        _ = failed.update(.saved(failedRequest, .commitFailed("offline"), destinationExists: true))
        XCTAssertEqual(failed.update(.dismiss), [.close])
    }

    func testEditorOpensAheadOfTheSelectionAndThePassageCatchesUp() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.begin(.text, context)), [.readSelection(context, .text)])
        XCTAssertEqual(state.update(.selectionPending(context)), [.show(.editor)])
        XCTAssertEqual(state.session?.phase, .editing(""))
        XCTAssertNil(state.session?.target)
        XCTAssertEqual(state.update(.selectionPending(context)), [], "a repeat is inert")
        XCTAssertEqual(state.update(.changeNote("Typed already")), [])

        let target = context.target(captured: selection)
        XCTAssertEqual(state.update(.selection(context, selection)), [.probe(target)],
            "the box is already up, so only provenance work starts")
        XCTAssertEqual(state.session?.target, target)
        XCTAssertEqual(state.session?.phase, .editing("Typed already"), "typing is kept")

        XCTAssertEqual(state.update(.selection(context, selection)), [], "a second passage is ignored")
    }

    func testSaveBeforeThePassageArrivesWaitsForItThenSaves() {
        var state = CaptureState()
        _ = state.update(.begin(.text, context))
        _ = state.update(.selectionPending(context))
        _ = state.update(.changeNote("Quick thought"))
        XCTAssertEqual(state.update(.save), [], "nothing to save against yet, and no beep")
        XCTAssertEqual(state.session?.saveAwaitsSelection, true)
        XCTAssertEqual(state.update(.changeNote("Edited late")), [], "the note is frozen while waiting")
        XCTAssertEqual(state.session?.phase, .editing("Quick thought"))

        let target = context.target(captured: selection)
        let effects = state.update(.selection(context, selection))
        guard case let .save(request)? = effects.last else { return XCTFail("expected a save, got \(effects)") }
        XCTAssertEqual(effects, [.probe(target), .save(request)])
        XCTAssertEqual(request.note.body, "Quick thought")
        XCTAssertEqual(request.target, target)
        XCTAssertEqual(state.session?.saveAwaitsSelection, false)

        var blank = CaptureState()
        _ = blank.update(.begin(.text, context))
        _ = blank.update(.selectionPending(context))
        XCTAssertEqual(blank.update(.save), [.beep], "a blank note still cannot be queued")
    }

    func testAFailedSelectionReadOpensTheEditorWithoutAPassage() {
        var state = CaptureState()
        _ = state.update(.begin(.text, context))
        let emptyTarget = context.target(captured: CapturedSelection(text: ""))
        XCTAssertEqual(state.update(.failed(context, "no focused element")), [.probe(emptyTarget), .show(.editor)])
        XCTAssertEqual(state.session?.phase, .editing(""))

        var early = CaptureState()
        _ = early.update(.begin(.text, context))
        _ = early.update(.selectionPending(context))
        XCTAssertEqual(early.update(.failed(context, "timed out")), [.probe(emptyTarget)])
        XCTAssertEqual(early.session?.target, emptyTarget)
    }

    private func editing(body: String) throws -> CaptureState {
        var state = CaptureState()
        XCTAssertEqual(state.update(.begin(.text, context)), [.readSelection(context, .text)])
        let target = context.target(captured: selection)
        XCTAssertEqual(state.update(.selection(context, selection)), [.probe(target), .show(.editor)])
        XCTAssertEqual(state.update(.changeNote(body)), [])
        return state
    }

    private func saving() throws -> (CaptureState, CaptureSaveRequest) {
        var state = try editing(body: "Draft")
        let effects = state.update(.save)
        guard case let .save(request)? = effects.first else {
            throw XCTSkip("Expected a save effect, got \(effects)")
        }
        return (state, request)
    }
}
