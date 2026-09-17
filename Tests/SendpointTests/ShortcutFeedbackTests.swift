import AppKit
import XCTest
@testable import Sendpoint

@MainActor
final class ShortcutFeedbackTests: XCTestCase {
    func testNoFeedbackHidesPanelAndClearsAnnouncement() {
        let projection = ShortcutFeedback(slots: [.capture], registrationIssues: [], feedback: nil)

        XCTAssertFalse(projection.isVisible)
        XCTAssertTrue(projection.issues.isEmpty)
        XCTAssertNil(projection.feedback)
        XCTAssertEqual(projection.announcement, "")
    }

    func testEmptyFeedbackStillShowsPanel() {
        let projection = ShortcutFeedback(slots: [], registrationIssues: [], feedback: "")

        XCTAssertTrue(projection.isVisible)
        XCTAssertEqual(projection.feedback, "")
        XCTAssertEqual(projection.announcement, "")
    }

    func testFeedbackWithoutIssuesIsUnchanged() {
        let projection = ShortcutFeedback(slots: [], registrationIssues: [], feedback: "Choose another shortcut.")

        XCTAssertTrue(projection.isVisible)
        XCTAssertEqual(projection.feedback, "Choose another shortcut.")
        XCTAssertEqual(projection.announcement, projection.feedback)
    }

    func testFiltersBySlotPreservingRegistrationOrderAndSharesFormattedText() {
        let combo = KeyCombo(keyCode: 0, modifiers: [.command])
        let projection = ShortcutFeedback(
            slots: [.capture, .dictate, .capture],
            registrationIssues: [
                .conflict(slot: .dictate, combo: combo, reason: .reserved("Example")),
                .invalid(slot: .copy, combo: combo),
                .invalid(slot: .capture, combo: combo),
            ],
            feedback: "Try again."
        )

        XCTAssertTrue(projection.isVisible)
        XCTAssertEqual(projection.issues.map(\.id), [.dictate, .capture])
        XCTAssertEqual(projection.issues.map(\.text), [
            "Dictate: That shortcut is reserved for Example.",
            "Typed note: Typed note has an invalid shortcut. Choose another one in Settings.",
        ])
        XCTAssertEqual(projection.announcement, (projection.issues.map(\.text) + ["Try again."]).joined(separator: " "))
    }

    func testExcludedIssuesDoNotShowPanel() {
        let projection = ShortcutFeedback(
            slots: [.capture],
            registrationIssues: [.invalid(slot: .copy, combo: KeyCombo(keyCode: 0, modifiers: []))],
            feedback: nil
        )

        XCTAssertFalse(projection.isVisible)
        XCTAssertEqual(projection.announcement, "")
    }

    func testEmptyFeedbackAfterIssuePreservesTrailingSeparator() {
        let issue = ShortcutRegistrationIssue.invalid(slot: .capture, combo: KeyCombo(keyCode: 0, modifiers: []))
        let withoutFeedback = ShortcutFeedback(slots: [.capture], registrationIssues: [issue], feedback: nil)
        let emptyFeedback = ShortcutFeedback(slots: [.capture], registrationIssues: [issue], feedback: "")

        XCTAssertTrue(withoutFeedback.isVisible)
        XCTAssertEqual(withoutFeedback.announcement, withoutFeedback.issues[0].text)
        XCTAssertEqual(emptyFeedback.announcement, withoutFeedback.announcement + " ")
    }
}
