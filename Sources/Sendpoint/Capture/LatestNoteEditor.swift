import Foundation
import Observation
import SendpointDomain

@Observable
final class LatestNoteEditor {
    struct Draft: Equatable {
        let sessionID = UUID()
        let stackID: UUID
        let stackName: String
        let original: Note
        var text: String
    }

    enum State {
        case closed, tornDown
        case editing(Draft), saving(Draft), confirmingDiscard(Draft)
        case failed(Draft, String, pending: Bool)

        var draft: Draft? {
            switch self {
            case let .editing(draft), let .saving(draft), let .confirmingDiscard(draft),
                 let .failed(draft, _, _): draft
            case .closed, .tornDown: nil
            }
        }
    }

    enum Event {
        case open, save, retry, dismiss, discard, keepEditing, teardown
        case text(String)
        case saved(UUID, StackMutationOutcome)
    }

    private(set) var state: State = .closed
    private(set) var focusRequest = 0
    @ObservationIgnored private let store: StackStore
    @ObservationIgnored private let blockedReason: () -> String?
    @ObservationIgnored var onPresent: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onMessage: (String) -> Void = { _ in }

    init(store: StackStore, blockedReason: @escaping () -> String? = { nil }) {
        self.store = store
        self.blockedReason = blockedReason
    }

    var isOpen: Bool { state.draft != nil }
    var isEditable: Bool {
        switch state {
        case .editing, .failed(_, _, pending: false): true
        default: false
        }
    }
    var hasPendingSave: Bool {
        switch state {
        case .saving, .failed(_, _, pending: true): true
        default: false
        }
    }
    var text: String {
        get { state.draft?.text ?? "" }
        set { send(.text(newValue)) }
    }

    func send(_ event: Event) {
        if case .tornDown = state { return }
        switch event {
        case .open:
            if isOpen {
                focusRequest += 1
                onPresent()
                return
            }
            if let reason = blockedReason() { onMessage(reason); return }
            guard store.state == .idle, !store.hasPendingMutations else {
                onMessage("Finish saving pending changes before editing a note.")
                return
            }
            // Recording time, not the user-controlled order of the stack.
            guard let note = store.currentNotes.max(by: { $0.createdAt < $1.createdAt }) else {
                onMessage("No notes to edit")
                return
            }
            state = .editing(Draft(
                stackID: store.currentStackID,
                stackName: stackTitle(store.stacks.number(of: store.currentStackID)!),
                original: note, text: note.body
            ))
            focusRequest += 1
            onPresent()
        case let .text(text):
            guard isEditable, var draft = state.draft else { return }
            draft.text = text
            state = .editing(draft)
        case .save:
            guard isEditable, let draft = state.draft else { return }
            if draft.text == draft.original.body { close(); return }
            guard store.state == .idle, !store.hasPendingMutations else {
                onMessage("Finish saving pending changes, then save this edit.")
                return
            }
            state = .saving(draft)
            store.mutate(.updateNoteBody(
                stackID: draft.stackID, noteID: draft.original.id,
                body: draft.text, expected: draft.original
            )) { [weak self] outcome in
                self?.send(.saved(draft.sessionID, outcome))
            }
        case let .saved(id, outcome):
            guard hasPendingSave, let draft = state.draft, draft.sessionID == id else { return }
            switch outcome {
            case .committed, .noOp: close()
            case let .commitFailed(message): state = .failed(draft, message, pending: true)
            case let .rejected(message): state = .failed(draft, message, pending: false)
            case .cancelled: state = .failed(draft, "Saving was cancelled. Your draft has been kept.", pending: false)
            }
        case .retry:
            guard case let .failed(draft, _, pending: true) = state else { return }
            state = .saving(draft)
            // Failed mutations stay in the store queue. Never enqueue a duplicate.
            store.retryPendingMutations()
        case .dismiss:
            guard !hasPendingSave, let draft = state.draft else { return }
            if draft.text == draft.original.body { close() }
            else { state = .confirmingDiscard(draft) }
        case .discard:
            guard case .confirmingDiscard = state else { return }
            close()
        case .keepEditing:
            guard case let .confirmingDiscard(draft) = state else { return }
            state = .editing(draft)
            focusRequest += 1
        case .teardown:
            state = .tornDown
            onClose()
            onPresent = {}
            onClose = {}
            onMessage = { _ in }
        }
    }

    private func close() {
        state = .closed
        onClose()
    }
}
