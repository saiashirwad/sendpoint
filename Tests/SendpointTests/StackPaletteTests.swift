import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

final class StackPaletteTests: XCTestCase {
    @MainActor
    func testCyclingPreviewUpdatesBothPanesWithoutMutatingTheCurrentStack() {
        var workflow = PaletteWorkflow()
        let first = Stack(name: "First", notes: [Note(subject: .standalone, body: "First note")])
        let second = Stack(name: "Second", notes: [Note(subject: .standalone, body: "Second note")])
        let template = Template.builtIns[0]
        let context = PaletteContext(stacks: [first, second], currentStackID: first.id,
            lastCleared: nil, templates: [template], activeTemplate: template)
        for stack in [second, first, second] {
            var update = PaletteUpdate(state: workflow, context: context, operationID: UUID(), now: Date())
            update.update(.previewStack(stack.id))
            workflow = update.state
            let view = PaletteProjection(state: workflow, context: context)
            XCTAssertEqual(workflow.presentation, .cycling)
            XCTAssertEqual(workflow.focusedPane, .stacks)
            XCTAssertEqual(view.shownStack?.id, stack.id)
            XCTAssertEqual(view.noteListing.notes.map(\.body), stack.notes.map(\.body))
            XCTAssertEqual(context.currentStackID, first.id)
            XCTAssertTrue(update.effects.isEmpty)
        }
        var update = PaletteUpdate(state: workflow, context: context, operationID: UUID(), now: Date())
        update.update(.key(.activate, textHasSelection: false))
        update.update(.chooseStack(first.id))
        XCTAssertTrue(update.effects.isEmpty, "Preview cannot commit or edit through browsing controls")
        XCTAssertEqual(update.state.stackState.selectedStackID, second.id)
        update.update(.close)
        update.update(.open(.notes, highlighting: first.id))
        XCTAssertEqual(update.state.presentation, .browsing)
        XCTAssertEqual(update.state.focusedPane, .notes)
    }

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

    func testStackPaneActionsFollowTheHighlightedStack() {
        let context = PaletteActionContext(
            pane: .stacks,
            focus: .stack(StackItemFacts(id: stackID, name: "crdt", noteCount: 3, isCurrent: false)),
            shownStack: nil,
            canDeleteStack: true,
            undo: StackUndoFacts(
                stackID: otherStackID, stackName: "Default", noteCount: 1,
                isCurrentStack: true),
            templateName: "Coherent"
        )
        let items = PaletteActionCatalog.items(for: context)
        XCTAssertEqual(items.map(\.action), [
            .switchToStack(stackID), .copyStack(stackID),
            .renameStack(stackID), .newStack, .chooseTemplate, .undoClear,
            .clearStack(stackID), .deleteStack(stackID),
        ])
        XCTAssertEqual(items.first?.title, "Switch to “crdt”")
        XCTAssertEqual(items.first?.keys, "↩")
        XCTAssertEqual(items.first { $0.action == .undoClear }?.title, "Undo Clear (1)")
        XCTAssertTrue(items.last?.isDestructive ?? false)

        let empty = PaletteActionCatalog.items(for: PaletteActionContext(
            pane: .stacks,
            focus: .stack(StackItemFacts(id: stackID, name: "crdt", noteCount: 0, isCurrent: true)),
            shownStack: nil, canDeleteStack: false, undo: nil, templateName: "Plain"
        ))
        XCTAssertEqual(empty.map(\.action), [
            .switchToStack(stackID), .renameStack(stackID), .newStack,
            .chooseTemplate,
        ], "an empty, only stack cannot be copied, cleared, or deleted")
        XCTAssertEqual(empty.first?.title, "Keep “crdt” current")

        let create = PaletteActionCatalog.items(for: PaletteActionContext(
            pane: .stacks, focus: .createStack(name: "New"), shownStack: nil,
            canDeleteStack: true, undo: nil, templateName: "Plain"
        ))
        XCTAssertEqual(create.map(\.action), [.createStack("New"), .chooseTemplate])
    }

    func testNotePaneActionsFollowTheHighlightedNoteAndShownStack() {
        let context = PaletteActionContext(
            pane: .notes,
            focus: .note(id: secondNoteID, index: 1, count: 3),
            shownStack: StackItemFacts(id: stackID, name: "crdt", noteCount: 3, isCurrent: false),
            canDeleteStack: true,
            undo: nil,
            templateName: "Coherent"
        )
        let items = PaletteActionCatalog.items(for: context)
        XCTAssertEqual(items.map(\.action), [
            .editNote(secondNoteID), .copyNote(secondNoteID),
            .moveNoteUp(secondNoteID), .moveNoteDown(secondNoteID), .deleteNote(secondNoteID),
            .switchToStack(stackID), .copyStack(stackID), .renameStack(stackID), .newStack,
            .chooseTemplate, .clearStack(stackID),
        ])
        XCTAssertEqual(items.first { $0.action == .switchToStack(stackID) }?.keys, "⌘↩")
        XCTAssertEqual(items.first { $0.action == .copyStack(stackID) }?.keys, "⇧⌘C")

        let last = PaletteActionCatalog.items(for: PaletteActionContext(
            pane: .notes,
            focus: .note(id: thirdNoteID, index: 2, count: 3),
            shownStack: StackItemFacts(id: stackID, name: "crdt", noteCount: 3, isCurrent: true),
            canDeleteStack: true, undo: nil, templateName: "Coherent"
        ))
        XCTAssertFalse(last.contains { $0.action == .moveNoteDown(thirdNoteID) }, "last note cannot move down")
        XCTAssertFalse(last.contains { $0.action == .switchToStack(stackID) }, "current stack needs no switch")

        let nothing = PaletteActionCatalog.items(for: PaletteActionContext(
            pane: .notes, focus: .nothing,
            shownStack: StackItemFacts(id: stackID, name: "crdt", noteCount: 0, isCurrent: true),
            canDeleteStack: true, undo: nil, templateName: "Coherent"
        ))
        XCTAssertEqual(nothing.map(\.action), [.renameStack(stackID), .newStack, .chooseTemplate])
    }

    func testActionFilterMatchesTitleAndSubtitle() {
        let items = PaletteActionCatalog.items(for: PaletteActionContext(
            pane: .stacks,
            focus: .stack(StackItemFacts(id: stackID, name: "crdt", noteCount: 3, isCurrent: false)),
            shownStack: nil, canDeleteStack: true, undo: nil, templateName: "Coherent"
        ))
        XCTAssertEqual(
            PaletteActionCatalog.filter(items, query: "del").map(\.action), [.deleteStack(stackID)])
        XCTAssertEqual(
            PaletteActionCatalog.filter(items, query: "coherent").map(\.action),
            [.copyStack(stackID), .chooseTemplate], "the template name appears in a subtitle")
        XCTAssertEqual(PaletteActionCatalog.filter(items, query: " ").count, items.count)
    }
}
