import XCTest
import SendpointDomain

final class AutomaticSelectionTrackerTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1_000)

    func testDragCopiedTextCanBeTakenByMatchingProcessAndPasteboardRevision() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = tracker.update(.mouseDragged)
        let request = mouseUp(&tracker)

        XCTAssertNotNil(request)
        XCTAssertEqual(
            tracker.update(.settle(
                request!,
                text: "Prime Agent output",
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            [.accepted]
        )
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt.addingTimeInterval(1)
            )),
            [.took("Prime Agent output")]
        )
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt.addingTimeInterval(1)
            )),
            []
        )
    }

    func testClickWithoutDragDoesNotCreateCandidate() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))

        XCTAssertNil(mouseUp(&tracker))
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 10,
                now: capturedAt
            )),
            []
        )
    }

    func testUnchangedOrEmptyPasteboardDoesNotCreateCandidate() {
        var unchanged = AutomaticSelectionTracker()
        _ = unchanged.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = unchanged.update(.mouseDragged)
        let unchangedRequest = mouseUp(&unchanged)!
        XCTAssertEqual(
            unchanged.update(.settle(
                unchangedRequest,
                text: "old clipboard text",
                pasteboardChangeCount: 10,
                now: capturedAt
            )),
            []
        )
        XCTAssertEqual(unchanged.phase, .settling(unchangedRequest))

        var empty = AutomaticSelectionTracker()
        _ = empty.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = empty.update(.mouseDragged)
        let emptyRequest = mouseUp(&empty)!
        XCTAssertEqual(
            empty.update(.settle(
                emptyRequest,
                text: "  \n",
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )
        XCTAssertEqual(empty.phase, .idle)
    }

    func testCandidateRejectsWrongProcessChangedPasteboardAndExpiredValue() {
        func makeTracker() -> AutomaticSelectionTracker {
            var tracker = AutomaticSelectionTracker()
            _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
            _ = tracker.update(.mouseDragged)
            let request = mouseUp(&tracker)!
            XCTAssertEqual(
                tracker.update(.settle(
                    request,
                    text: "selection",
                    pasteboardChangeCount: 11,
                    now: capturedAt
                )),
                [.accepted]
            )
            return tracker
        }

        var wrongProcess = makeTracker()
        XCTAssertEqual(
            wrongProcess.update(.take(
                processIdentifier: 99,
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )

        var changedPasteboard = makeTracker()
        XCTAssertEqual(
            changedPasteboard.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 12,
                now: capturedAt
            )),
            []
        )

        var expired = makeTracker()
        XCTAssertEqual(
            expired.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt.addingTimeInterval(16)
            )),
            []
        )
    }

    func testPendingSettlementCanObserveDelayedClipboardWrite() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = tracker.update(.mouseDragged)
        let request = mouseUp(&tracker)!

        XCTAssertEqual(
            tracker.update(.settle(
                request,
                text: "old clipboard text",
                pasteboardChangeCount: 10,
                now: capturedAt
            )),
            []
        )
        XCTAssertEqual(
            tracker.update(.settlePending(
                text: "delayed selection",
                pasteboardChangeCount: 11,
                now: capturedAt.addingTimeInterval(0.15)
            )),
            [.accepted]
        )
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt.addingTimeInterval(0.15)
            )),
            [.took("delayed selection")]
        )
    }

    func testAbandonedSettlementRejectsLaterClipboardChange() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = tracker.update(.mouseDragged)
        let request = mouseUp(&tracker)!

        XCTAssertEqual(tracker.update(.abandon(request)), [])

        XCTAssertEqual(
            tracker.update(.settlePending(
                text: "unrelated later copy",
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )
    }

    func testNewDragRejectsLateSettlementFromEarlierDrag() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = tracker.update(.mouseDragged)
        let staleRequest = mouseUp(&tracker)!

        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 11))
        _ = tracker.update(.mouseDragged)
        let currentRequest = mouseUp(&tracker)!

        XCTAssertEqual(
            tracker.update(.settle(
                staleRequest,
                text: "stale",
                pasteboardChangeCount: 12,
                now: capturedAt
            )),
            []
        )
        XCTAssertEqual(
            tracker.update(.settle(
                currentRequest,
                text: "current",
                pasteboardChangeCount: 12,
                now: capturedAt
            )),
            [.accepted]
        )
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 12,
                now: capturedAt
            )),
            [.took("current")]
        )
    }

    func testTeardownIsIdempotentAndRejectsLateEvents() {
        var tracker = AutomaticSelectionTracker()
        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 10))
        _ = tracker.update(.mouseDragged)
        let request = mouseUp(&tracker)!

        XCTAssertEqual(tracker.update(.teardown), [.cancelSettlement])
        XCTAssertEqual(tracker.update(.teardown), [])
        XCTAssertEqual(
            tracker.update(.settle(
                request,
                text: "late",
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )

        _ = tracker.update(.mouseDown(processIdentifier: 42, pasteboardChangeCount: 11))
        _ = tracker.update(.mouseDragged)
        XCTAssertNil(mouseUp(&tracker))
        XCTAssertEqual(
            tracker.update(.take(
                processIdentifier: 42,
                pasteboardChangeCount: 11,
                now: capturedAt
            )),
            []
        )
    }

    private func mouseUp(_ tracker: inout AutomaticSelectionTracker) -> AutomaticSelectionRequest? {
        let effects = tracker.update(.mouseUp)
        guard case let .beginSettlement(request) = effects.first else { return nil }
        return request
    }
}
