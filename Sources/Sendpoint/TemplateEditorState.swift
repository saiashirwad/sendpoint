import SendpointDomain
import Foundation
import Observation

enum TemplateEditorError: Error, Equatable, LocalizedError {
    case unsavedChanges

    var errorDescription: String? { "Save or discard the template changes first." }
}
@Observable
final class TemplateEditorState {
    enum SelectionResult: Equatable {
        case selected
        case unchanged
        case needsDecision
        case rejected
    }

    enum DirtyDecision: Equatable {
        case save
        case saveAsNew(name: String)
        case discard
        case cancel
    }

    private let settings: TemplateSettings
    private let makeID: () -> UUID
    private let onChange: () -> Void

    private(set) var editedTemplateID: UUID
    var draft: Template
    private(set) var pendingTemplateID: UUID?

    init(settings: TemplateSettings, makeID: @escaping () -> UUID = UUID.init,
         onChange: @escaping () -> Void = {}) {
        self.settings = settings
        self.makeID = makeID
        self.onChange = onChange
        let template = settings.activeTemplate
        editedTemplateID = template.id
        draft = template
    }

    var storedTemplate: Template? { settings.template(id: editedTemplateID) }
    var isDirty: Bool { storedTemplate != draft }
    var canDelete: Bool { settings.templates.count > 1 }
    var templates: [Template] { settings.templates }

    @discardableResult
    func requestSelection(_ id: UUID) -> SelectionResult {
        guard settings.template(id: id) != nil else { return .rejected }
        guard id != editedTemplateID else { return .unchanged }
        guard isDirty else {
            selectImmediately(id)
            return .selected
        }
        pendingTemplateID = id
        return .needsDecision
    }

    func validatedNewTemplateName(_ name: String) throws -> String {
        try settings.validatedName(name, excluding: nil)
    }

    func save() throws {
        try settings.updateTemplate(draft)
        draft = settings.template(id: editedTemplateID) ?? draft
        onChange()
    }

    @discardableResult
    func saveAsNew(named name: String) throws -> UUID {
        let clone = Template(
            id: makeID(),
            name: name,
            preamble: draft.preamble,
            includeTimestamps: draft.includeTimestamps,
            includeHeading: draft.includeHeading,
            includeNoteNumbers: draft.includeNoteNumbers,
            clearStackAfterExport: draft.clearStackAfterExport
        )
        try settings.addTemplate(clone)
        selectImmediately(clone.id)
        return clone.id
    }

    func revert() {
        guard let storedTemplate else { return }
        draft = storedTemplate
        pendingTemplateID = nil
    }

    func delete() throws {
        guard !isDirty else { throw TemplateEditorError.unsavedChanges }
        selectImmediately(try settings.deleteTemplate(id: editedTemplateID))
    }

    func saveAndSelectPending() throws {
        guard let pendingTemplateID else { return }
        try save()
        selectImmediately(pendingTemplateID)
    }

    func saveAsNewAndSelectPending(named name: String) throws {
        guard let destination = pendingTemplateID else { return }
        _ = try saveAsNew(named: name)
        selectImmediately(destination)
    }

    func discardAndSelectPending() {
        guard let pendingTemplateID else { return }
        selectImmediately(pendingTemplateID)
    }

    func cancelPendingSelection() {
        pendingTemplateID = nil
    }

    @discardableResult
    func resolvePendingSelection(_ decision: DirtyDecision) throws -> Bool {
        guard pendingTemplateID != nil else { return true }
        switch decision {
        case .save:
            try saveAndSelectPending()
        case let .saveAsNew(name):
            try saveAsNewAndSelectPending(named: name)
        case .discard:
            discardAndSelectPending()
        case .cancel:
            cancelPendingSelection()
            return false
        }
        return true
    }

    @discardableResult
    func resolveClose(_ decision: DirtyDecision) throws -> Bool {
        guard isDirty else { return true }
        switch decision {
        case .save:
            try save()
        case let .saveAsNew(name):
            _ = try saveAsNew(named: name)
        case .discard:
            revert()
        case .cancel:
            return false
        }
        return true
    }

    private func selectImmediately(_ id: UUID) {
        guard let template = settings.template(id: id) else { return }
        try? settings.selectTemplate(id: id)
        editedTemplateID = id
        draft = template
        pendingTemplateID = nil
        onChange()
    }
}
