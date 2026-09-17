import SendpointDomain
import Foundation
import SwiftUI
import XCTest
@testable import Sendpoint

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

final class NoteRevealAnchorTests: XCTestCase {
    func testFullyVisibleNoteNeedsNoScroll() {
        XCTAssertNil(noteRevealAnchor(frame: CGRect(x: 0, y: 40, width: 300, height: 60), viewportHeight: 400))
        XCTAssertNil(noteRevealAnchor(frame: CGRect(x: 0, y: 0, width: 300, height: 400), viewportHeight: 400))
    }

    func testNoteCutOffAboveRevealsAtTop() {
        XCTAssertEqual(noteRevealAnchor(frame: CGRect(x: 0, y: -12, width: 300, height: 60), viewportHeight: 400), .top)
    }

    func testNoteCutOffBelowRevealsAtBottom() {
        XCTAssertEqual(noteRevealAnchor(frame: CGRect(x: 0, y: 380, width: 300, height: 60), viewportHeight: 400), .bottom)
    }
}

final class RevealedScrollOffsetTests: XCTestCase {
    func testBottomAnchorPutsTheNoteAtTheBottomEdgeWithMargin() {
        let top = revealedScrollOffset(
            currentTop: 0, frame: CGRect(x: 0, y: 380, width: 300, height: 120),
            viewportHeight: 400, contentHeight: 1000, anchor: .bottom
        )
        XCTAssertEqual(top, 106)
    }

    func testTopAnchorPutsTheNoteAtTheTopEdgeWithMargin() {
        let top = revealedScrollOffset(
            currentTop: 300, frame: CGRect(x: 0, y: -50, width: 300, height: 80),
            viewportHeight: 400, contentHeight: 1000, anchor: .top
        )
        XCTAssertEqual(top, 244)
    }

    func testOffsetIsClampedToTheContent() {
        XCTAssertEqual(revealedScrollOffset(
            currentTop: 500, frame: CGRect(x: 0, y: 390, width: 300, height: 200),
            viewportHeight: 400, contentHeight: 1000, anchor: .bottom
        ), 600)
        XCTAssertEqual(revealedScrollOffset(
            currentTop: 10, frame: CGRect(x: 0, y: -30, width: 300, height: 40),
            viewportHeight: 400, contentHeight: 1000, anchor: .top
        ), 0)
        XCTAssertEqual(revealedScrollOffset(
            currentTop: 0, frame: CGRect(x: 0, y: 100, width: 300, height: 40),
            viewportHeight: 400, contentHeight: 300, anchor: .bottom
        ), 0)
    }
}

final class StackStatusDetailTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testEmptyStackSaysSo() {
        XCTAssertEqual(stackStatusDetail(noteCount: 0, latest: nil, calendar: calendar), "Nothing captured yet")
    }

    func testCountsNotesAndDatesTheLatest() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21))!
        let latest = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 20, minute: 48))!
        XCTAssertEqual(
            stackStatusDetail(noteCount: 6, latest: latest, now: now, calendar: calendar),
            "6 notes · \(noteTimestampLabel(latest, now: now, calendar: calendar))"
        )
        XCTAssertEqual(
            stackStatusDetail(noteCount: 1, latest: latest, now: now, calendar: calendar).prefix(7),
            "1 note "
        )
    }
}

final class NoteTimeLabelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testTimeLabelIsJustTheTime() {
        let at = date(2026, 9, 15, 20)
        XCTAssertEqual(noteTimeLabel(at, calendar: calendar), at.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute()))
    }
}

final class NoteTimestampLabelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 5) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testSameDayShowsOnlyTheTime() {
        let now = date(2026, 9, 15, 20, 0)
        let label = noteTimestampLabel(date(2026, 9, 15, 14, 32), now: now, calendar: calendar)
        XCTAssertTrue(label.contains("32"), label)
        XCTAssertFalse(label.contains("Sep"), label)
        XCTAssertFalse(label.contains("2026"), label)
    }

    func testSameYearShowsDayAndMonthWithoutYear() {
        let now = date(2026, 9, 15)
        let label = noteTimestampLabel(date(2026, 3, 2), now: now, calendar: calendar)
        XCTAssertTrue(label.contains("2"), label)
        XCTAssertFalse(label.contains("2026"), label)
        XCTAssertFalse(label.contains(":"), label)
    }

    func testOtherYearShowsTheYear() {
        let now = date(2026, 9, 15)
        let label = noteTimestampLabel(date(2024, 12, 31), now: now, calendar: calendar)
        XCTAssertTrue(label.contains("2024"), label)
        XCTAssertFalse(label.contains(":"), label)
    }
}

final class NoteLabelStyleCacheTests: XCTestCase {
    private func calendar(identifier: Calendar.Identifier, timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func fresh(
        _ date: Date, calendar: Calendar,
        _ derive: (Date.FormatStyle) -> Date.FormatStyle
    ) -> String {
        let base = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(derive(base))
    }

    func testCachedStylesMatchFreshFormatting() {
        let calendars = [
            calendar(identifier: .gregorian, timeZone: "UTC"),
            calendar(identifier: .gregorian, timeZone: "America/New_York"),
            calendar(identifier: .buddhist, timeZone: "Pacific/Auckland"),
        ]
        for calendar in calendars {
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21))!
            let sameDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 20, minute: 7))!
            let sameYear = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9, minute: 5))!
            let otherYear = calendar.date(from: DateComponents(year: 2024, month: 12, day: 31, hour: 9, minute: 5))!
            for _ in 0..<2 {
                XCTAssertEqual(
                    noteTimeLabel(sameDay, calendar: calendar),
                    fresh(sameDay, calendar: calendar) { $0.hour().minute() }
                )
                XCTAssertEqual(
                    noteTimestampLabel(sameDay, now: now, calendar: calendar),
                    fresh(sameDay, calendar: calendar) { $0.hour().minute() }
                )
                XCTAssertEqual(
                    noteTimestampLabel(sameYear, now: now, calendar: calendar),
                    fresh(sameYear, calendar: calendar) { $0.day().month(.abbreviated) }
                )
                XCTAssertEqual(
                    noteTimestampLabel(otherYear, now: now, calendar: calendar),
                    fresh(otherYear, calendar: calendar) { $0.day().month(.abbreviated).year() }
                )
            }
        }
    }
}
