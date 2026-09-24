import Foundation

public nonisolated struct LatestNoteDraft: Equatable, Sendable {
    public let sessionID: UUID
    public let stackID: UUID
    public let stackName: String
    public let original: Note
    public var text: String

    public init(
        sessionID: UUID = UUID(),
        stackID: UUID,
        stackName: String,
        original: Note,
        text: String
    ) {
        self.sessionID = sessionID
        self.stackID = stackID
        self.stackName = stackName
        self.original = original
        self.text = text
    }
}

public nonisolated enum LatestNoteState: Equatable, Sendable {
    case closed, tornDown
    case editing(LatestNoteDraft), saving(LatestNoteDraft), confirmingDiscard(LatestNoteDraft)
    case failed(LatestNoteDraft, String, pending: Bool)

    public var draft: LatestNoteDraft? {
        switch self {
        case let .editing(draft), let .saving(draft), let .confirmingDiscard(draft),
             let .failed(draft, _, _): draft
        case .closed, .tornDown: nil
        }
    }

    public var isEditable: Bool {
        switch self {
        case .editing, .failed(_, _, pending: false): true
        default: false
        }
    }

    public var hasPendingSave: Bool {
        switch self {
        case .saving, .failed(_, _, pending: true): true
        default: false
        }
    }

    public mutating func update(_ event: LatestNoteEvent) -> [LatestNoteEffect] {
        guard self != .tornDown else { return [] }
        switch event {
        case .teardown:
            self = .tornDown
            return [.close]
        case .open:
            guard draft != nil else { return [] }
            return [.present]
        case let .began(draft):
            guard self == .closed else { return [] }
            self = .editing(draft)
            return [.present]
        case let .rejected(message):
            guard self == .closed else { return [] }
            return [.message(message)]
        case let .text(text):
            guard isEditable, var draft else { return [] }
            draft.text = text
            self = .editing(draft)
            return []
        case .save:
            guard isEditable, let draft else { return [] }
            if draft.text == draft.original.body {
                self = .closed
                return [.close]
            }
            self = .saving(draft)
            return [.mutate(.updateNoteBody(
                stackID: draft.stackID, noteID: draft.original.id,
                body: draft.text, expected: draft.original
            ), session: draft.sessionID)]
        case let .saveRefused(message):
            guard isEditable else { return [] }
            return [.message(message)]
        case let .saved(id, outcome):
            guard hasPendingSave, let draft, draft.sessionID == id else { return [] }
            switch outcome {
            case .committed, .noOp:
                self = .closed
                return [.close]
            case let .commitFailed(message):
                self = .failed(draft, message, pending: true)
            case let .rejected(message):
                self = .failed(draft, message, pending: false)
            case .cancelled:
                self = .failed(draft, "Saving was cancelled. Your draft has been kept.", pending: false)
            }
            return []
        case .retry:
            guard case let .failed(draft, _, pending: true) = self else { return [] }
            self = .saving(draft)
            return [.retry]
        case .dismiss:
            guard !hasPendingSave, let draft else { return [] }
            if draft.text == draft.original.body {
                self = .closed
                return [.close]
            }
            self = .confirmingDiscard(draft)
            return []
        case .discard:
            guard case .confirmingDiscard = self else { return [] }
            self = .closed
            return [.close]
        case .keepEditing:
            guard case let .confirmingDiscard(draft) = self else { return [] }
            self = .editing(draft)
            return [.focus]
        }
    }
}

public nonisolated enum LatestNoteEvent: Equatable, Sendable {
    case open
    case began(LatestNoteDraft)
    case rejected(String)
    case text(String)
    case save
    case saveRefused(String)
    case saved(UUID, StackMutationOutcome)
    case retry
    case dismiss
    case discard
    case keepEditing
    case teardown
}

public nonisolated enum LatestNoteEffect: Equatable, Sendable {
    case present
    case focus
    case close
    case message(String)
    case mutate(StackDocumentMutation, session: UUID)
    case retry
}
