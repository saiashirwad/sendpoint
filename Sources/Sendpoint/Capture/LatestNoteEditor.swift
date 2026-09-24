import Foundation
import Observation
import SendpointDomain

@Observable
final class LatestNoteEditor {
    private(set) var state: LatestNoteState = .closed
    private(set) var focusRequest = 0
    @ObservationIgnored private let store: StackStore
    @ObservationIgnored private let blockedReason: () -> String?
    @ObservationIgnored var onPresent: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onMessage: (String) -> Void = { _ in }
    @ObservationIgnored private var pending: [LatestNoteEvent] = []
    @ObservationIgnored private var isDraining = false

    init(store: StackStore, blockedReason: @escaping () -> String? = { nil }) {
        self.store = store
        self.blockedReason = blockedReason
    }

    var isOpen: Bool { state.draft != nil }
    var isEditable: Bool { state.isEditable }
    var hasPendingSave: Bool { state.hasPendingSave }
    var text: String {
        get { state.draft?.text ?? "" }
        set { send(.text(newValue)) }
    }

    func send(_ event: LatestNoteEvent) {
        guard state != .tornDown else { return }
        pending.append(resolved(event))
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            var next = state
            let effects = next.update(pending.removeFirst())
            if next != state { state = next }
            run(effects)
        }
        isDraining = false
    }

    private func resolved(_ event: LatestNoteEvent) -> LatestNoteEvent {
        switch event {
        case .open: resolvedOpen()
        case .save: resolvedSave()
        default: event
        }
    }

    private func resolvedOpen() -> LatestNoteEvent {
        if state.draft != nil { return .open }
        if let reason = blockedReason() { return .rejected(reason) }
        guard store.state == .idle, !store.hasPendingMutations else {
            return .rejected("Finish saving pending changes before editing a note.")
        }
        // Recording time, not the user-controlled order of the stack.
        guard let note = store.currentNotes.max(by: { $0.createdAt < $1.createdAt }) else {
            return .rejected("No notes to edit")
        }
        return .began(LatestNoteDraft(
            stackID: store.currentStackID,
            stackName: stackTitle(store.stacks.number(of: store.currentStackID)!),
            original: note,
            text: note.body
        ))
    }

    private func resolvedSave() -> LatestNoteEvent {
        guard state.isEditable, let draft = state.draft else { return .save }
        if draft.text == draft.original.body { return .save }
        guard store.state == .idle, !store.hasPendingMutations else {
            return .saveRefused("Finish saving pending changes, then save this edit.")
        }
        return .save
    }

    private func run(_ effects: [LatestNoteEffect]) {
        for effect in effects {
            switch effect {
            case .present:
                focusRequest += 1
                onPresent()
            case .focus:
                focusRequest += 1
            case .close:
                onClose()
                if case .tornDown = state {
                    onPresent = {}
                    onClose = {}
                    onMessage = { _ in }
                }
            case let .message(text):
                onMessage(text)
            case let .mutate(mutation, session):
                store.mutate(mutation) { [weak self] outcome in
                    self?.send(.saved(session, outcome))
                }
            case .retry:
                // Failed mutations stay in the store queue. Never enqueue a duplicate.
                store.retryPendingMutations()
            }
        }
    }
}
