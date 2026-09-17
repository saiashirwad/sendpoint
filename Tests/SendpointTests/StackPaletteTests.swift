import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

final class StackPaletteTests: XCTestCase {
    private let stackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let otherStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
    private let firstNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let secondNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let thirdNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    private var notes: [Note] {
        [
            Note(
                id: firstNoteID,
                subject: .selection(quote: "OT scales quadratically"),
                body: "Can you explain why?"
            ),
            Note(
                id: secondNoteID,
                subject: .standalone,
                body: "Monoids and semi-groups"
            ),
            Note(
                id: thirdNoteID,
                subject: .selection(quote: "join-semilattice"),
                body: ""
            ),
        ]
    }

    func testNoteHighlightWrapsAndConfines() {
        let ids = [firstNoteID, secondNoteID, thirdNoteID]
        var state = NoteHighlightState()
        XCTAssertNil(state.highlight)

        state.move(by: -1, in: ids)
        XCTAssertEqual(state.highlight, thirdNoteID, "moving up with no highlight lands on the last note")
        state.move(by: 1, in: ids)
        XCTAssertEqual(state.highlight, firstNoteID, "wraps from the bottom")
        state.move(by: 1, in: ids)
        XCTAssertEqual(state.highlight, secondNoteID)

        state.confine(to: [firstNoteID, secondNoteID])
        XCTAssertEqual(state.highlight, secondNoteID, "a still-listed highlight stays put")
        state.confine(to: [thirdNoteID])
        XCTAssertEqual(state.highlight, thirdNoteID, "an unlisted highlight falls to the first note")
        state.confine(to: [])
        XCTAssertNil(state.highlight)
    }

    private func stack(noteCount: Int) -> StackItemFacts {
        StackItemFacts(id: stackID, number: 2, noteCount: noteCount, isCurrent: true, startedAt: nil)
    }

    func testNoteActionsComeFirstThenTheCurrentStacksThenTheTemplate() {
        let items = PaletteActionCatalog.items(for: PaletteActionContext(
            focus: .note(id: secondNoteID, index: 1, count: 3),
            stack: stack(noteCount: 3),
            undo: StackUndoFacts(stackID: otherStackID, stackName: "Stack 1", noteCount: 1, isCurrentStack: false),
            templateName: "Coherent"
        ))
        XCTAssertEqual(items.map(\.action), [
            .editNote(secondNoteID), .copyNote(secondNoteID),
            .moveNoteUp(secondNoteID), .moveNoteDown(secondNoteID), .deleteNote(secondNoteID),
            .copyStack, .undoClear, .clearStack, .chooseTemplate,
        ])
        XCTAssertEqual(items.first?.section, .note)
        XCTAssertEqual(items.first?.keys, "↩")
        XCTAssertEqual(items.first { $0.action == .copyStack }?.keys, "⇧⌘C")
        XCTAssertEqual(items.first { $0.action == .clearStack }?.section, .stack)
        XCTAssertTrue(items.first { $0.action == .clearStack }?.isDestructive ?? false)
        XCTAssertEqual(items.first { $0.action == .undoClear }?.title, "Undo Clear in Stack 1 (1)")
        XCTAssertEqual(items.last?.section, .template)

        let last = PaletteActionCatalog.items(for: PaletteActionContext(
            focus: .note(id: thirdNoteID, index: 2, count: 3),
            stack: stack(noteCount: 3), undo: nil, templateName: "Coherent"
        ))
        XCTAssertFalse(last.contains { $0.action == .moveNoteDown(thirdNoteID) }, "last note cannot move down")
    }

    func testAnEmptyStackCanOnlyChangeTheTemplateOrUndoAClear() {
        let nothing = PaletteActionCatalog.items(for: PaletteActionContext(
            focus: .nothing, stack: stack(noteCount: 0), undo: nil, templateName: "Coherent"
        ))
        XCTAssertEqual(nothing.map(\.action), [.chooseTemplate])

        let cleared = PaletteActionCatalog.items(for: PaletteActionContext(
            focus: .nothing, stack: stack(noteCount: 0),
            undo: StackUndoFacts(stackID: stackID, stackName: "Stack 2", noteCount: 3, isCurrentStack: true),
            templateName: "Coherent"
        ))
        XCTAssertEqual(cleared.map(\.action), [.undoClear, .chooseTemplate])
    }

    func testMenuLeavesOutPinnedActionsAndMatchesTitleAndSection() {
        let items = PaletteActionCatalog.items(for: PaletteActionContext(
            focus: .note(id: secondNoteID, index: 1, count: 3),
            stack: stack(noteCount: 3),
            undo: StackUndoFacts(stackID: stackID, stackName: "Stack 2", noteCount: 1, isCurrentStack: true),
            templateName: "Coherent"
        ))
        XCTAssertEqual(
            PaletteActionCatalog.menu(items, query: "").map(\.action),
            [.editNote(secondNoteID), .copyNote(secondNoteID), .moveNoteUp(secondNoteID), .moveNoteDown(secondNoteID),
             .deleteNote(secondNoteID), .copyStack, .clearStack],
            "⌘Z and ⌘P are already shown on the palette itself")
        XCTAssertEqual(PaletteActionCatalog.menu(items, query: "clear").map(\.action), [.clearStack])
        XCTAssertEqual(
            PaletteActionCatalog.menu(items, query: "stack").map(\.action), [.copyStack, .clearStack],
            "the section name matches every action in its section")
        XCTAssertTrue(PaletteActionCatalog.menu(items, query: "template").isEmpty)
    }
}
