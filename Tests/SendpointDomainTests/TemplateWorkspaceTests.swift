import Foundation
import XCTest
import SendpointDomain

final class TemplateWorkspaceTests: XCTestCase {
    func testUnknownSelectionDoesNotChangeTheWorkspace() {
        var state = make()
        let before = state
        XCTAssertEqual(state.update(.request(.template(UUID()))), .failure(.validation(.unknownTemplate)))
        XCTAssertEqual(state, before)
    }

    func testDirtyDeleteRefusesWithoutChangingTheDraft() {
        var state = make(edited: .learn)
        _ = state.update(.editPreamble("Dirty"))
        let dirty = state
        XCTAssertEqual(state.update(.delete), .failure(.unsavedChanges))
        XCTAssertEqual(state, dirty)
    }

    func testCancelledAndStaleDecisionsDoNothing() {
        var state = make(edited: .learn)
        _ = state.update(.editPreamble("Dirty"))
        XCTAssertEqual(state.update(.request(.template(Template.plain.id))), .success(.needsDecision))
        XCTAssertEqual(state.session?.pendingDestination, .template(Template.plain.id))
        XCTAssertEqual(state.update(.resolve(.cancel)), .success(.cancelled))
        XCTAssertNil(state.session?.pendingDestination)
        XCTAssertEqual(state.session?.draft.preamble, "Dirty")
        XCTAssertEqual(state.collection.activeTemplateID, Template.learn.id)
        let cancelled = state
        XCTAssertEqual(state.update(.resolve(.save)), .success(.unchanged))
        XCTAssertEqual(state.update(.resolve(.discard)), .success(.unchanged))
        XCTAssertEqual(state, cancelled)
    }

    func testSaveCommitsAndNormalizesDraftInOneTransition() {
        var state = make()
        _ = state.update(.editName("  Work  "))
        _ = state.update(.editPreamble("Changed"))
        XCTAssertEqual(state.collection.activeTemplate, .plain)
        XCTAssertEqual(state.update(.save), .success(.changed))
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.session?.draft, state.collection.activeTemplate)
        XCTAssertEqual(state.collection.activeTemplate.name, "Work")
        XCTAssertEqual(state.collection.activeTemplate.preamble, "Changed")
    }

    func testSaveAsNewCommitsCloneThenNavigatesToPendingDestination() {
        for destination in [TemplateDestination.template(Template.plain.id), .close] {
            var state = make(edited: .learn)
            _ = state.update(.editPreamble("Clone"))
            _ = state.update(.editIncludeNoteNumbers(true))
            _ = state.update(.editClearStackAfterExport(false))
            _ = state.update(.request(destination))
            let id = UUID()
            XCTAssertEqual(
                state.update(.resolve(.saveAsNew(name: " Copy ", id: id))),
                .success(destination == .close ? .closed : .changed)
            )
            XCTAssertEqual(state.collection.template(id: Template.learn.id), .learn)
            let clone = state.collection.template(id: id)
            XCTAssertEqual(clone?.name, "Copy")
            XCTAssertEqual(clone?.preamble, "Clone")
            XCTAssertEqual(clone?.includeNoteNumbers, true)
            XCTAssertEqual(clone?.clearStackAfterExport, false)
            XCTAssertEqual(state.collection.activeTemplateID, destination == .close ? id : Template.plain.id)
            XCTAssertFalse(state.isDirty)
            XCTAssertNil(state.session?.pendingDestination)
        }
    }

    func testFailedValidationPreservesEntireDraftAndPendingNavigation() {
        for destination in [TemplateDestination.template(Template.steer.id), .close] {
            var state = make(edited: .learn)
            _ = state.update(.editName(" plain "))
            _ = state.update(.editPreamble("Unsaved"))
            _ = state.update(.request(destination))
            let before = state
            XCTAssertEqual(state.update(.resolve(.save)), .failure(.validation(.duplicateName)))
            XCTAssertEqual(state, before)
            XCTAssertEqual(
                state.update(.resolve(.saveAsNew(name: " ", id: UUID()))),
                .failure(.validation(.emptyName))
            )
            XCTAssertEqual(state, before)
            XCTAssertEqual(
                state.update(.resolve(.saveAsNew(name: "Unique", id: Template.plain.id))),
                .failure(.validation(.duplicateID))
            )
            XCTAssertEqual(state, before)
            _ = state.update(.editName("Saved"))
            XCTAssertEqual(state.update(.resolve(.save)), .success(destination == .close ? .closed : .changed))
            XCTAssertEqual(state.collection.template(id: Template.learn.id)?.name, "Saved")
        }
    }

    func testCleanNavigationAndCloseDoNotNeedDecisions() {
        var state = make()
        XCTAssertEqual(state.update(.request(.template(Template.plain.id))), .success(.unchanged))
        XCTAssertEqual(state.update(.request(.template(Template.learn.id))), .success(.changed))
        XCTAssertEqual(state.session?.draft, .learn)
        XCTAssertEqual(state.update(.request(.close)), .success(.closed))
        XCTAssertNil(state.session?.pendingDestination)
    }

    func testExplicitSaveAsNewClearsAbandonedNavigation() {
        var state = make()
        _ = state.update(.editName("Learn"))
        _ = state.update(.request(.close))
        XCTAssertEqual(state.update(.resolve(.save)), .failure(.validation(.duplicateName)))
        let id = UUID()
        XCTAssertEqual(state.update(.saveAsNew(name: "New", id: id)), .success(.changed))
        XCTAssertEqual(state.collection.activeTemplateID, id)
        XCTAssertNil(state.session?.pendingDestination)
        let saved = state
        XCTAssertEqual(state.update(.resolve(.save)), .success(.unchanged))
        XCTAssertEqual(state, saved)
    }

    func testEndEditingIsIdempotentAndLateEditorEventsAreIgnored() {
        var state = make()
        _ = state.update(.editPreamble("Unsaved"))
        _ = state.update(.request(.close))
        XCTAssertEqual(state.update(.endEditing), .success(.changed))
        let closed = state
        XCTAssertEqual(state.update(.endEditing), .success(.unchanged))
        for event in [TemplateWorkspaceEvent.editName("Late"), .save, .delete, .resolve(.save)] {
            XCTAssertEqual(state.update(event), .success(.unchanged))
            XCTAssertEqual(state, closed)
        }
        XCTAssertEqual(state.collection.activeTemplate, .plain)
        _ = state.update(.request(.template(Template.steer.id)))
        XCTAssertNil(state.session)
        _ = state.update(.beginEditing)
        XCTAssertEqual(state.session?.draft, .steer)
        let reopened = state
        XCTAssertEqual(state.update(.beginEditing), .success(.unchanged))
        XCTAssertEqual(state, reopened)
    }

    private func make(edited: Template = .plain) -> TemplateWorkspace {
        var state = TemplateWorkspace(collection: TemplateCollection(activeTemplateID: edited.id))
        _ = state.update(.request(.template(edited.id)))
        _ = state.update(.beginEditing)
        return state
    }
}
