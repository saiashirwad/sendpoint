import Foundation
import XCTest
import SendpointDomain

final class TemplateEditorStateTests: XCTestCase {
    func testUnknownSelectionDoesNotChangeTheEditor() {
        var state = make()
        let id = UUID()

        XCTAssertEqual(state.update(.requestSelection(id)), [])
        XCTAssertNil(state.pendingTemplateID)
        XCTAssertEqual(state.editedTemplateID, Template.plain.id)
        XCTAssertEqual(state.draft, .plain)
    }

    func testDirtyDeleteRefusesWithoutChangingTheDraft() {
        var state = make(edited: .coherent)
        _ = state.update(.editPreamble("Dirty"))
        let dirty = state

        XCTAssertEqual(state.update(.delete), [.unsavedChanges])
        XCTAssertEqual(state, dirty)
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.draft.preamble, "Dirty")
    }

    func testCancelledAndStaleDecisionsDoNothing() {
        var state = make(edited: .coherent)
        _ = state.update(.editPreamble("Dirty"))
        XCTAssertEqual(state.update(.requestSelection(Template.plain.id)), [])
        XCTAssertEqual(state.pendingTemplateID, Template.plain.id)

        XCTAssertEqual(state.update(.resolvePendingSelection(.cancel, id: nil)), [])
        XCTAssertNil(state.pendingTemplateID)
        XCTAssertEqual(state.draft.preamble, "Dirty")
        XCTAssertEqual(state.editedTemplateID, Template.coherent.id)

        let cancelled = state
        XCTAssertEqual(state.update(.resolvePendingSelection(.save, id: nil)), [])
        XCTAssertEqual(state.update(.saveAndSelectPending), [])
        XCTAssertEqual(state.update(.resolveClose(.cancel, id: nil)), [])
        XCTAssertEqual(state, cancelled)

        _ = state.update(.revert)
        let clean = state
        XCTAssertFalse(state.isDirty)
        XCTAssertNil(state.pendingTemplateID)
        XCTAssertEqual(state.update(.resolveClose(.save, id: nil)), [])
        XCTAssertEqual(state.update(.resolveClose(.cancel, id: nil)), [])
        XCTAssertEqual(state, clean)
    }

    func testSaveDoesNotLookSavedUntilTheStoredTemplateArrives() {
        var state = make()
        _ = state.update(.editPreamble("Changed"))
        let dirty = state

        XCTAssertEqual(state.update(.save), [.updateStoredTemplate(dirty.draft, thenSelect: nil)])
        XCTAssertEqual(state, dirty)

        XCTAssertEqual(
            state.update(.storedTemplate(.coherent, templates: state.templates, thenSelect: nil)),
            []
        )
        XCTAssertEqual(state, dirty)

        let stored = dirty.draft
        let templates = dirty.templates.map { $0.id == stored.id ? stored : $0 }
        XCTAssertEqual(
            state.update(.storedTemplate(stored, templates: templates, thenSelect: nil)),
            [.notify]
        )
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.draft, stored)
        XCTAssertEqual(state.editedTemplateID, Template.plain.id)
    }

    func testSaveAsNewSelectsTheCloneBeforeThePendingDestination() {
        var state = make(edited: .coherent)
        _ = state.update(.editPreamble("Clone"))
        _ = state.update(.requestSelection(Template.plain.id))
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let clone = Template(
            id: id,
            name: "Copy",
            preamble: "Clone",
            includeTimestamps: Template.coherent.includeTimestamps,
            includeHeading: Template.coherent.includeHeading,
            includeNoteNumbers: Template.coherent.includeNoteNumbers,
            clearStackAfterExport: Template.coherent.clearStackAfterExport
        )

        XCTAssertEqual(
            state.update(.saveAsNewAndSelectPending(name: "Copy", id: id)),
            [.addTemplate(clone, thenSelect: Template.plain.id)]
        )
        XCTAssertEqual(state.editedTemplateID, Template.coherent.id)
        XCTAssertEqual(state.draft.preamble, "Clone")

        var templates = Template.builtIns
        templates.append(clone)
        XCTAssertEqual(
            state.update(.addedTemplate(clone, templates: templates, thenSelect: Template.plain.id)),
            [.selectTemplate(id: id, thenSelect: Template.plain.id)]
        )
        XCTAssertEqual(state.editedTemplateID, Template.coherent.id)

        XCTAssertEqual(
            state.update(.selectedTemplate(clone, templates: templates, thenSelect: Template.plain.id)),
            [.notify, .selectTemplate(id: Template.plain.id, thenSelect: nil)]
        )
        XCTAssertEqual(state.editedTemplateID, id)
        XCTAssertEqual(state.draft, clone)

        XCTAssertEqual(
            state.update(.selectedTemplate(.plain, templates: templates, thenSelect: nil)),
            [.notify]
        )
        XCTAssertEqual(state.editedTemplateID, Template.plain.id)
        XCTAssertEqual(state.draft, .plain)
        XCTAssertNil(state.pendingTemplateID)
        XCTAssertEqual(state.templates, templates)
    }

    private func make(edited: Template = .plain) -> TemplateEditorState {
        TemplateEditorState(templates: Template.builtIns, editedTemplateID: edited.id, draft: edited)
    }
}
