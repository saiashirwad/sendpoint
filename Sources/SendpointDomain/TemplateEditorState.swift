import Foundation

public nonisolated enum TemplateEditorError: Error, Equatable, Sendable, LocalizedError {
    case unsavedChanges

    public var errorDescription: String? { "Save or discard the template changes first." }
}

public nonisolated enum TemplateEditorSelectionResult: Equatable, Sendable {
    case selected
    case unchanged
    case needsDecision
    case rejected
}

public nonisolated enum TemplateEditorDirtyDecision: Equatable, Sendable {
    case save
    case saveAsNew(name: String)
    case discard
    case cancel
}

public nonisolated enum TemplateEditorEvent: Equatable, Sendable {
    case editName(String)
    case editPreamble(String)
    case editIncludeNoteNumbers(Bool)
    case editIncludeTimestamps(Bool)
    case editIncludeHeading(Bool)
    case editClearStackAfterExport(Bool)
    case requestSelection(UUID)
    case save
    case saveAsNew(name: String, id: UUID)
    case revert
    case delete
    case saveAndSelectPending
    case saveAsNewAndSelectPending(name: String, id: UUID)
    case discardAndSelectPending
    case cancelPendingSelection
    case resolvePendingSelection(TemplateEditorDirtyDecision, id: UUID?)
    case resolveClose(TemplateEditorDirtyDecision, id: UUID?)
    case storedTemplate(Template, templates: [Template], thenSelect: UUID?)
    case addedTemplate(Template, templates: [Template], thenSelect: UUID?)
    case selectedTemplate(Template, templates: [Template], thenSelect: UUID?)
    case deletedTemplate(templates: [Template], next: UUID)
    case teardown
}

public nonisolated enum TemplateEditorEffect: Equatable, Sendable {
    case updateStoredTemplate(Template, thenSelect: UUID?)
    case addTemplate(Template, thenSelect: UUID?)
    case selectTemplate(id: UUID, thenSelect: UUID?)
    case deleteTemplate(UUID)
    case notify
    case unsavedChanges
}

public nonisolated struct TemplateEditorState: Equatable, Sendable {
    public typealias SelectionResult = TemplateEditorSelectionResult
    public typealias DirtyDecision = TemplateEditorDirtyDecision

    public enum Lifecycle: Equatable, Sendable {
        case live
        case tornDown
    }

    public var lifecycle: Lifecycle = .live
    public var templates: [Template]
    public var editedTemplateID: UUID
    public var draft: Template
    public var pendingTemplateID: UUID?

    public init(templates: [Template], editedTemplateID: UUID, draft: Template) {
        self.templates = templates
        self.editedTemplateID = editedTemplateID
        self.draft = draft
    }

    public var isTornDown: Bool { lifecycle == .tornDown }

    public var storedTemplate: Template? {
        templates.first { $0.id == editedTemplateID }
    }

    public var isDirty: Bool { storedTemplate != draft }

    public var canDelete: Bool { templates.count > 1 }

    public mutating func update(_ event: TemplateEditorEvent) -> [TemplateEditorEffect] {
        guard lifecycle != .tornDown else { return [] }
        switch event {
        case .teardown:
            lifecycle = .tornDown
            return []
        case let .editName(name):
            draft.name = name
            return []
        case let .editPreamble(preamble):
            draft.preamble = preamble
            return []
        case let .editIncludeNoteNumbers(include):
            draft.includeNoteNumbers = include
            return []
        case let .editIncludeTimestamps(include):
            draft.includeTimestamps = include
            return []
        case let .editIncludeHeading(include):
            draft.includeHeading = include
            return []
        case let .editClearStackAfterExport(clear):
            draft.clearStackAfterExport = clear
            return []
        case let .requestSelection(id):
            guard templates.contains(where: { $0.id == id }) else { return [] }
            guard id != editedTemplateID else { return [] }
            guard isDirty else { return [.selectTemplate(id: id, thenSelect: nil)] }
            pendingTemplateID = id
            return []
        case .save:
            return [.updateStoredTemplate(draft, thenSelect: nil)]
        case let .saveAsNew(name, id):
            return [.addTemplate(clone(name: name, id: id), thenSelect: nil)]
        case .revert:
            guard let storedTemplate else { return [] }
            draft = storedTemplate
            pendingTemplateID = nil
            return []
        case .delete:
            guard !isDirty else { return [.unsavedChanges] }
            return [.deleteTemplate(editedTemplateID)]
        case .saveAndSelectPending:
            guard let pendingTemplateID else { return [] }
            return [.updateStoredTemplate(draft, thenSelect: pendingTemplateID)]
        case let .saveAsNewAndSelectPending(name, id):
            guard let pendingTemplateID else { return [] }
            return [.addTemplate(clone(name: name, id: id), thenSelect: pendingTemplateID)]
        case .discardAndSelectPending:
            guard let pendingTemplateID else { return [] }
            return [.selectTemplate(id: pendingTemplateID, thenSelect: nil)]
        case .cancelPendingSelection:
            pendingTemplateID = nil
            return []
        case let .resolvePendingSelection(decision, id):
            guard pendingTemplateID != nil else { return [] }
            switch decision {
            case .save:
                return update(.saveAndSelectPending)
            case let .saveAsNew(name):
                guard let id else { return [] }
                return update(.saveAsNewAndSelectPending(name: name, id: id))
            case .discard:
                return update(.discardAndSelectPending)
            case .cancel:
                pendingTemplateID = nil
                return []
            }
        case let .resolveClose(decision, id):
            guard isDirty else { return [] }
            switch decision {
            case .save:
                return update(.save)
            case let .saveAsNew(name):
                guard let id else { return [] }
                return update(.saveAsNew(name: name, id: id))
            case .discard:
                return update(.revert)
            case .cancel:
                return []
            }
        case let .storedTemplate(template, templates, thenSelect):
            guard template.id == editedTemplateID else { return [] }
            self.templates = templates
            draft = template
            if let thenSelect {
                return [.notify, .selectTemplate(id: thenSelect, thenSelect: nil)]
            }
            return [.notify]
        case let .addedTemplate(template, templates, thenSelect):
            self.templates = templates
            return [.selectTemplate(id: template.id, thenSelect: thenSelect)]
        case let .selectedTemplate(template, templates, thenSelect):
            self.templates = templates
            editedTemplateID = template.id
            draft = template
            pendingTemplateID = nil
            if let thenSelect, thenSelect != template.id {
                return [.notify, .selectTemplate(id: thenSelect, thenSelect: nil)]
            }
            return [.notify]
        case let .deletedTemplate(templates, next):
            self.templates = templates
            return [.selectTemplate(id: next, thenSelect: nil)]
        }
    }

    private func clone(name: String, id: UUID) -> Template {
        Template(
            id: id,
            name: name,
            preamble: draft.preamble,
            includeTimestamps: draft.includeTimestamps,
            includeHeading: draft.includeHeading,
            includeNoteNumbers: draft.includeNoteNumbers,
            clearStackAfterExport: draft.clearStackAfterExport
        )
    }
}
