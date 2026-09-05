import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

/// The save half of the capture reducer: a typed note becomes one exact
/// request, and only that request's outcome can move the capture on.
final class CaptureSaveLifecycleTests: XCTestCase {
    private let context = AnnotationCaptureContext(
        sessionID: UUID(), createdAt: Date(timeIntervalSince1970: 123)
    )
    private let selection = CapturedSelection(
        text: "Selection", appName: "Reader", appBundleID: "com.example.reader",
        processIdentifier: 42, screenRect: nil
    )

    func testSaveFreezesTheNoteAndRetryReusesTheExactRequest() throws {
        var state = try editing(note: "Keep this draft")
        let target = try XCTUnwrap(state.session?.target)

        let effects = state.update(.save)
        let request = CaptureSaveRequest(
            target: target, destinationSessionID: context.sessionID,
            annotation: try XCTUnwrap(target.annotation(note: "Keep this draft"))
        )
        XCTAssertEqual(effects, [.save(request)])
        XCTAssertEqual(state.update(.changeNote("A late edit")), [])
        XCTAssertEqual(state.session?.phase, .saving(request))

        XCTAssertEqual(state.update(.prepared(request, request.annotation)), [.commit(request)])
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
        XCTAssertEqual(state, .idle)
    }

    func testMissingDestinationKeepsTheAnnotationForAnExplicitRetarget() throws {
        var (state, request) = try saving()
        XCTAssertEqual(
            state.update(.saved(request, .rejected("The target session no longer exists."), destinationExists: false)),
            [.show(.editor)]
        )
        XCTAssertEqual(state.session?.phase, .saveFailed(
            request, message: "That stack was deleted.", retryable: false, targetMissing: true
        ))
        XCTAssertEqual(state.update(.retry), [])

        let destination = UUID()
        let retargeted = CaptureSaveRequest(
            target: request.target, destinationSessionID: destination, annotation: request.annotation
        )
        XCTAssertEqual(state.update(.retarget(destination)), [.abandon(request.target), .save(retargeted)])
        XCTAssertEqual(state.session?.phase, .saving(retargeted))
        XCTAssertEqual(state.update(.prepared(retargeted, retargeted.annotation)), [.commit(retargeted)])
        XCTAssertEqual(state.update(.saved(retargeted, .committed, destinationExists: true)), [.close])
    }

    func testRejectedExistingDestinationCannotRetargetAndDismissAbandonsProvenance() throws {
        var (state, request) = try saving()
        _ = state.update(.saved(request, .rejected("The annotation already exists."), destinationExists: true))
        XCTAssertEqual(state.session?.phase, .saveFailed(
            request, message: "The annotation already exists.", retryable: false, targetMissing: false
        ))
        XCTAssertEqual(state.update(.retarget(UUID())), [])
        XCTAssertEqual(state.update(.dismiss), [.abandon(request.target), .close])
    }

    func testStaleOutcomesAreIgnored() throws {
        var (state, request) = try saving()
        let otherAnnotation = Annotation(
            subject: .standalone, note: "Other", provenance: request.annotation.provenance
        )
        for stale in [
            CaptureSaveRequest(target: request.target, destinationSessionID: UUID(), annotation: request.annotation),
            CaptureSaveRequest(target: request.target, destinationSessionID: request.destinationSessionID,
                annotation: otherAnnotation),
        ] {
            XCTAssertEqual(state.update(.prepared(stale, stale.annotation)), [])
            XCTAssertEqual(state.update(.saved(stale, .committed, destinationExists: true)), [])
            XCTAssertEqual(state.session?.phase, .saving(request))
        }
        XCTAssertEqual(state.update(.prepared(request, otherAnnotation)), [], "the prepared annotation must keep its id")
    }

    func testNoOpAndCancellationNeverClaimSuccess() throws {
        for outcome in [AnnotationStoreMutationOutcome.noOp, .cancelled] {
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
        var editing = try editing(note: "")
        let target = try XCTUnwrap(editing.session?.target)
        XCTAssertEqual(editing.update(.save), [.beep], "a blank note cannot be saved")
        XCTAssertEqual(editing.update(.begin(.text, context)), [.focusEditor])
        XCTAssertEqual(editing.update(.dismiss), [.abandon(target), .close])

        var (queued, request) = try saving()
        XCTAssertEqual(queued.update(.begin(.text, context)), [.beep])
        XCTAssertEqual(queued.update(.dismiss), [.close], "a queued save keeps its provenance work")
        XCTAssertEqual(queued.update(.saved(request, .committed, destinationExists: true)), [])
        XCTAssertEqual(queued, .idle)

        var (failed, failedRequest) = try saving()
        _ = failed.update(.saved(failedRequest, .commitFailed("offline"), destinationExists: true))
        XCTAssertEqual(failed.update(.dismiss), [.close])
    }

    private func editing(note: String) throws -> CaptureState {
        var state = CaptureState.idle
        XCTAssertEqual(state.update(.begin(.text, context)), [.readSelection(context, .text)])
        let target = context.target(captured: selection)
        XCTAssertEqual(state.update(.selection(context, selection)), [.probe(target), .show(.editor)])
        XCTAssertEqual(state.update(.changeNote(note)), [])
        return state
    }

    private func saving() throws -> (CaptureState, CaptureSaveRequest) {
        var state = try editing(note: "Draft")
        let effects = state.update(.save)
        guard case let .save(request)? = effects.first else {
            throw XCTSkip("Expected a save effect, got \(effects)")
        }
        return (state, request)
    }
}
