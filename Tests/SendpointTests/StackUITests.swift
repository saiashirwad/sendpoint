import SendpointDomain
import Foundation
import SwiftUI
import XCTest
@testable import Sendpoint

final class StackUITests: XCTestCase {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testSingleStackCannotBeDeleted() {
        let facts = StackUIFacts(
            stacks: [Stack(id: firstID, name: "Only")],
            currentStackID: firstID,
            lastCleared: nil
        )

        XCTAssertFalse(facts.canDelete)

        let cleared = [makeNote("Cleared")]
        let deletion = StackDeletionFacts(
            stackID: firstID,
            stacks: [
                Stack(id: firstID, name: "Cleared"),
                Stack(id: secondID, name: "Other"),
            ],
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )
        XCTAssertTrue(deletion.requiresConfirmation)
        XCTAssertTrue(deletion.includesUndoBatch)
        XCTAssertEqual(deletion.noteCount, 1)
    }

    func testUndoFactsIdentifyANoncurrentSourceStack() {
        let cleared = [makeNote("One"), makeNote("Two")]
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: secondID,
            lastCleared: ClearedBatch(stackID: firstID, notes: cleared)
        )

        XCTAssertEqual(facts.undo?.stackID, firstID)
        XCTAssertEqual(facts.undo?.title, "Undo Clear in Reading (2)")
        XCTAssertEqual(facts.undo?.notification, "Cleared 2 notes in Reading")
    }

    func testNameDraftTrimsAndRejectsBlankOrFoldedDuplicates() {
        let stacks = [Stack(id: firstID, name: "Résumé")]

        XCTAssertEqual(
            StackNameDraft(text: "  New Notes  ", excludedStackID: nil)
                .validation(stacks: stacks),
            .valid("New Notes")
        )
        XCTAssertEqual(
            StackNameDraft(text: " \n ", excludedStackID: nil)
                .validation(stacks: stacks),
            .invalid("Enter a stack name.")
        )
        for duplicate in ["résumé", "RESUME", "ＲＥＳＵＭＥ"] {
            XCTAssertEqual(
                StackNameDraft(text: duplicate, excludedStackID: nil)
                    .validation(stacks: stacks),
                .invalid("A stack with that name already exists.")
            )
        }
    }

    func testRenameDraftExcludesCapturedStackButNotOtherStacks() {
        let stacks = [
            Stack(id: firstID, name: "Reading"),
            Stack(id: secondID, name: "Writing"),
        ]

        XCTAssertEqual(
            StackNameDraft(text: " reading ", excludedStackID: firstID)
                .validation(stacks: stacks),
            .valid("reading")
        )
        XCTAssertEqual(
            StackNameDraft(text: "WRITING", excludedStackID: firstID)
                .validation(stacks: stacks),
            .invalid("A stack with that name already exists.")
        )
    }

    func testQuickSwitchStateKeepsExplicitSelectionAndFallsBackAfterDeletion() {
        let both = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )
        var state = QuickSwitchState()
        state.synchronize(with: both)
        XCTAssertEqual(state.selectedStackID, firstID)
        XCTAssertEqual(state.choose(secondID, from: both), secondID)
        XCTAssertEqual(state.selectedStackID, secondID)
        XCTAssertNil(state.choose(UUID(), from: both))
        XCTAssertEqual(state.selectedStackID, secondID)
        state.selectCurrent(from: both)
        XCTAssertEqual(state.selectedStackID, firstID)
        _ = state.choose(secondID, from: both)

        let afterDeletion = StackUIFacts(
            stacks: [Stack(id: firstID, name: "Reading")],
            currentStackID: firstID,
            lastCleared: nil
        )
        state.synchronize(with: afterDeletion)
        XCTAssertEqual(state.selectedStackID, firstID)
    }

    private func makeNote(_ body: String) -> Note {
        Note(
            subject: .standalone,
            body: body
        )
    }
}

extension StackUITests {
    func testQuickSwitchListingFiltersAndOffersCreation() {
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )

        let everything = QuickSwitchListing(facts: facts, query: "   ")
        XCTAssertEqual(everything.stacks.map(\.id), [firstID, secondID])
        XCTAssertNil(everything.creatableName)

        let partial = QuickSwitchListing(facts: facts, query: "ITI")
        XCTAssertEqual(partial.stacks.map(\.id), [secondID])
        XCTAssertEqual(partial.creatableName, "ITI")
        XCTAssertEqual(partial.rows, [.stack(secondID), .create("ITI")])

        let existing = QuickSwitchListing(facts: facts, query: " reading ")
        XCTAssertEqual(existing.stacks.map(\.id), [firstID])
        XCTAssertNil(existing.creatableName, "an existing name is not offered for creation")

        let none = QuickSwitchListing(facts: facts, query: "zzz")
        XCTAssertTrue(none.stacks.isEmpty)
        XCTAssertEqual(none.rows, [.create("zzz")])
    }

    func testQuickSwitchStateMovesThroughRowsAndConfinesToListing() {
        let facts = StackUIFacts(
            stacks: [
                Stack(id: firstID, name: "Reading"),
                Stack(id: secondID, name: "Writing"),
            ],
            currentStackID: firstID,
            lastCleared: nil
        )
        let rows: [QuickSwitchRow] = [.stack(firstID), .stack(secondID), .create("New")]

        var state = QuickSwitchState()
        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .stack(firstID))

        state.move(by: -1, in: rows)
        XCTAssertEqual(state.highlight, .create("New"), "moving up from the top wraps")
        XCTAssertNil(state.selectedStackID)

        state.move(by: 1, in: rows)
        XCTAssertEqual(state.highlight, .stack(firstID), "moving down from the bottom wraps")

        state.move(by: 1, in: rows)
        XCTAssertEqual(state.selectedStackID, secondID)

        state.confine(to: [.stack(secondID)], preferring: firstID)
        XCTAssertEqual(state.highlight, .stack(secondID), "a still-listed highlight is kept")

        state.confine(to: [.create("Wri")], preferring: firstID)
        XCTAssertEqual(state.highlight, .create("Wri"), "otherwise the first listed row wins")

        state.confine(to: [.stack(secondID), .stack(firstID)], preferring: firstID)
        XCTAssertEqual(state.highlight, .stack(firstID), "the current stack is preferred when listed")

        state.move(by: 1, in: [])
        XCTAssertEqual(state.highlight, .stack(firstID), "an empty listing leaves the highlight alone")

        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .stack(firstID))
        state.highlight(.create("Draft"))
        state.synchronize(with: facts)
        XCTAssertEqual(state.highlight, .create("Draft"), "stack changes keep a create highlight")
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
        // Viewport 400, content 1000, currently at the top; note spans 380...500 in the viewport.
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

final class NoteDaySectionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func note(_ at: Date) -> Note {
        Note(subject: .standalone, body: "n", createdAt: at)
    }

    func testGroupsConsecutiveNotesByDayInOrder() {
        let now = date(2026, 9, 15, 21)
        let notes = [
            note(date(2025, 12, 31)), note(date(2026, 9, 12)), note(date(2026, 9, 12, 18)),
            note(date(2026, 9, 14)), note(date(2026, 9, 15, 8)), note(date(2026, 9, 15, 20)),
        ]
        let sections = noteDaySections(notes, now: now, calendar: calendar)
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        XCTAssertEqual(sections.map(\.label), [
            date(2025, 12, 31).formatted(style.day().month(.abbreviated).year()),
            date(2026, 9, 12).formatted(style.day().month(.abbreviated)),
            "Yesterday", "Today",
        ])
        XCTAssertEqual(sections.map(\.notes.count), [1, 2, 1, 2])
        XCTAssertEqual(sections.last?.notes.map(\.id), Array(notes.suffix(2)).map(\.id))
    }

    func testEmptyListHasNoSections() {
        XCTAssertTrue(noteDaySections([], calendar: calendar).isEmpty)
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
