import Foundation

public enum TemplateDestination: Equatable, Sendable {
    case template(UUID)
    case close
}

public enum TemplateDirtyDecision: Equatable, Sendable {
    case save
    case saveAsNew(name: String, id: UUID)
    case discard
    case cancel
}

public enum TemplateWorkspaceEvent: Equatable, Sendable {
    case beginEditing
    case endEditing
    case editName(String)
    case editPreamble(String)
    case editIncludeNoteNumbers(Bool)
    case editIncludeTimestamps(Bool)
    case editIncludeHeading(Bool)
    case editClearStackAfterExport(Bool)
    case request(TemplateDestination)
    case resolve(TemplateDirtyDecision)
    case save
    case saveAsNew(name: String, id: UUID)
    case revert
    case delete
}

public enum TemplateWorkspaceOutcome: Equatable, Sendable {
    case unchanged
    case changed
    case needsDecision
    case closed
    case cancelled
}

public enum TemplateWorkspaceError: Error, Equatable, Sendable, LocalizedError {
    case validation(TemplateError)
    case unsavedChanges

    public var errorDescription: String? {
        switch self {
        case let .validation(error): error.errorDescription
        case .unsavedChanges: "Save or discard the template changes first."
        }
    }
}

public struct TemplateWorkspace: Equatable, Sendable {
    public struct EditingSession: Equatable, Sendable {
        public fileprivate(set) var draft: Template
        public fileprivate(set) var pendingDestination: TemplateDestination?
    }

    public private(set) var collection: TemplateCollection
    public private(set) var session: EditingSession?

    public init(collection: TemplateCollection = TemplateCollection()) {
        self.collection = collection
    }

    public var isDirty: Bool {
        guard let session else { return false }
        return collection.template(id: session.draft.id) != session.draft
    }

    public mutating func update(
        _ event: TemplateWorkspaceEvent
    ) -> Result<TemplateWorkspaceOutcome, TemplateWorkspaceError> {
        var candidate = self
        do {
            let outcome = try candidate.apply(event)
            if candidate == self, outcome == .changed { return .success(.unchanged) }
            self = candidate
            return .success(outcome)
        } catch let error as TemplateError {
            return .failure(.validation(error))
        } catch {
            return .failure(.unsavedChanges)
        }
    }

    private mutating func apply(_ event: TemplateWorkspaceEvent) throws -> TemplateWorkspaceOutcome {
        switch event {
        case .beginEditing:
            guard session == nil else { return .unchanged }
            session = EditingSession(draft: collection.activeTemplate)
        case .endEditing:
            guard session != nil else { return .unchanged }
            session = nil
        case let .request(destination):
            if case let .template(id) = destination {
                guard collection.template(id: id) != nil else { throw TemplateError.unknownTemplate }
                guard id != collection.activeTemplateID else { return .unchanged }
            }
            if isDirty {
                session?.pendingDestination = destination
                return .needsDecision
            }
            return try navigate(to: destination)
        default:
            guard session != nil else { return .unchanged }
            switch event {
            case let .editName(value): session?.draft.name = value
            case let .editPreamble(value): session?.draft.preamble = value
            case let .editIncludeNoteNumbers(value): session?.draft.includeNoteNumbers = value
            case let .editIncludeTimestamps(value): session?.draft.includeTimestamps = value
            case let .editIncludeHeading(value): session?.draft.includeHeading = value
            case let .editClearStackAfterExport(value): session?.draft.clearStackAfterExport = value
            case .save:
                try save()
            case let .saveAsNew(name, id):
                try saveAsNew(name: name, id: id)
            case .revert:
                session = EditingSession(draft: collection.activeTemplate)
            case .delete:
                guard !isDirty else { throw TemplateWorkspaceError.unsavedChanges }
                try collection.delete(id: collection.activeTemplateID)
                session = EditingSession(draft: collection.activeTemplate)
            case let .resolve(decision):
                guard let destination = session?.pendingDestination else { return .unchanged }
                switch decision {
                case .save: try save()
                case let .saveAsNew(name, id): try saveAsNew(name: name, id: id)
                case .discard: break
                case .cancel:
                    session?.pendingDestination = nil
                    return .cancelled
                }
                return try navigate(to: destination)
            case .beginEditing, .endEditing, .request:
                preconditionFailure("Handled above")
            }
        }
        return .changed
    }

    private mutating func save() throws {
        guard let draft = session?.draft else { return }
        try collection.update(draft)
        session?.draft = collection.activeTemplate
    }

    private mutating func saveAsNew(name: String, id: UUID) throws {
        guard let draft = session?.draft else { return }
        let clone = Template(
            id: id, name: name, preamble: draft.preamble,
            includeTimestamps: draft.includeTimestamps, includeHeading: draft.includeHeading,
            includeNoteNumbers: draft.includeNoteNumbers, clearStackAfterExport: draft.clearStackAfterExport
        )
        try collection.add(clone)
        try collection.select(id: id)
        session = EditingSession(draft: collection.activeTemplate)
    }

    private mutating func navigate(to destination: TemplateDestination) throws -> TemplateWorkspaceOutcome {
        switch destination {
        case let .template(id):
            try collection.select(id: id)
            if session != nil { session = EditingSession(draft: collection.activeTemplate) }
            return .changed
        case .close:
            if session != nil { session = EditingSession(draft: collection.activeTemplate) }
            return .closed
        }
    }
}
