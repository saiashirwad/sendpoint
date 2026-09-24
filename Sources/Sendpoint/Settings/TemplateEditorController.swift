import Foundation
import Observation
import SendpointDomain

@Observable
final class TemplateEditorController {
    private(set) var state: TemplateEditorState
    @ObservationIgnored private let settings: TemplateSettings
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private var onChange: () -> Void
    @ObservationIgnored private var pending: [TemplateEditorEvent] = []
    @ObservationIgnored private var isDraining = false
    @ObservationIgnored private var failure: Error?

    init(
        settings: TemplateSettings,
        makeID: @escaping () -> UUID = UUID.init,
        onChange: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.makeID = makeID
        self.onChange = onChange
        let template = settings.activeTemplate
        state = TemplateEditorState(
            templates: settings.templates,
            editedTemplateID: template.id,
            draft: template
        )
    }

    var editedTemplateID: UUID { state.editedTemplateID }
    var draft: Template { state.draft }
    var pendingTemplateID: UUID? { state.pendingTemplateID }
    var storedTemplate: Template? { state.storedTemplate }
    var isDirty: Bool { state.isDirty }
    var canDelete: Bool { state.canDelete }
    var templates: [Template] { state.templates }

    func send(_ event: TemplateEditorEvent) {
        try? transact(event)
    }

    @discardableResult
    func requestSelection(_ id: UUID) -> TemplateEditorState.SelectionResult {
        let before = state
        send(.requestSelection(id))
        if state.pendingTemplateID == id, state.editedTemplateID == before.editedTemplateID {
            return .needsDecision
        }
        if state.editedTemplateID == id, id != before.editedTemplateID {
            return .selected
        }
        if id == state.editedTemplateID {
            return .unchanged
        }
        return .rejected
    }

    func validatedNewTemplateName(_ name: String) throws -> String {
        try settings.validatedName(name, excluding: nil)
    }

    func save() throws {
        try transact(.save)
    }

    @discardableResult
    func saveAsNew(named name: String) throws -> UUID {
        let id = makeID()
        try transact(.saveAsNew(name: name, id: id))
        return id
    }

    func revert() {
        send(.revert)
    }

    func delete() throws {
        try transact(.delete)
    }

    func saveAndSelectPending() throws {
        guard state.pendingTemplateID != nil else { return }
        try transact(.saveAndSelectPending)
    }

    func saveAsNewAndSelectPending(named name: String) throws {
        guard state.pendingTemplateID != nil else { return }
        try transact(.saveAsNewAndSelectPending(name: name, id: makeID()))
    }

    func discardAndSelectPending() {
        send(.discardAndSelectPending)
    }

    func cancelPendingSelection() {
        send(.cancelPendingSelection)
    }

    @discardableResult
    func resolvePendingSelection(_ decision: TemplateEditorState.DirtyDecision) throws -> Bool {
        guard state.pendingTemplateID != nil else { return true }
        switch decision {
        case .cancel:
            send(.resolvePendingSelection(.cancel, id: nil))
            return false
        case .save:
            try transact(.resolvePendingSelection(.save, id: nil))
        case let .saveAsNew(name):
            try transact(.resolvePendingSelection(.saveAsNew(name: name), id: makeID()))
        case .discard:
            send(.resolvePendingSelection(.discard, id: nil))
        }
        return true
    }

    @discardableResult
    func resolveClose(_ decision: TemplateEditorState.DirtyDecision) throws -> Bool {
        switch decision {
        case .cancel:
            let dirty = state.isDirty
            send(.resolveClose(.cancel, id: nil))
            return !dirty
        case .save:
            try transact(.resolveClose(.save, id: nil))
        case .discard:
            send(.resolveClose(.discard, id: nil))
        case let .saveAsNew(name):
            guard state.isDirty else { return true }
            try transact(.resolveClose(.saveAsNew(name: name), id: makeID()))
        }
        return true
    }

    func teardown() {
        guard !state.isTornDown else { return }
        send(.teardown)
        onChange = {}
    }

    private func transact(_ event: TemplateEditorEvent) throws {
        failure = nil
        enqueue(event)
        if let failure {
            let error = failure
            self.failure = nil
            throw error
        }
    }

    private func enqueue(_ event: TemplateEditorEvent) {
        pending.append(event)
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while !pending.isEmpty {
            if failure != nil {
                pending.removeAll()
                return
            }
            var next = state
            let effects = next.update(pending.removeFirst())
            if next != state { state = next }
            run(effects)
        }
    }

    // A thrown settings call returns before the follow-up, so the draft stays unsaved.
    private func run(_ effects: [TemplateEditorEffect]) {
        for effect in effects {
            if failure != nil { return }
            switch effect {
            case .unsavedChanges:
                failure = TemplateEditorError.unsavedChanges
                return
            case let .updateStoredTemplate(template, thenSelect):
                do {
                    try settings.updateTemplate(template)
                } catch {
                    failure = error
                    return
                }
                let stored = settings.template(id: template.id) ?? template
                enqueue(.storedTemplate(stored, templates: settings.templates, thenSelect: thenSelect))
            case let .addTemplate(template, thenSelect):
                do {
                    try settings.addTemplate(template)
                } catch {
                    failure = error
                    return
                }
                let stored = settings.template(id: template.id) ?? template
                enqueue(.addedTemplate(stored, templates: settings.templates, thenSelect: thenSelect))
            case let .selectTemplate(id, thenSelect):
                guard let template = settings.template(id: id) else { return }
                try? settings.selectTemplate(id: id)
                enqueue(.selectedTemplate(template, templates: settings.templates, thenSelect: thenSelect))
            case let .deleteTemplate(id):
                let next: UUID
                do {
                    next = try settings.deleteTemplate(id: id)
                } catch {
                    failure = error
                    return
                }
                enqueue(.deletedTemplate(templates: settings.templates, next: next))
            case .notify:
                onChange()
            }
        }
    }
}
