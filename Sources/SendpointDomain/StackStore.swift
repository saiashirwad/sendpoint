import Foundation
import Observation

public enum StackStoreError: Error, Equatable, Sendable {
    case mutationRejected(String)
    case commitFailed(String)
    case tornDown
}

public enum StackMutationOutcome: Equatable, Sendable {
    case committed
    case noOp
    case rejected(String)
    case commitFailed(String)
    case cancelled
}

@MainActor
@Observable
public final class StackStore {
    public enum State: Equatable, Sendable {
        case idle
        case processing
        case halted
        case tornDown
    }

    private enum CommitOutcome {
        case committed
        case failed(String)
        case cancelled
    }

    private struct QueuedMutation {
        let mutation: StackDocumentMutation
        let operationID: UUID
        let outcome: (@MainActor @Sendable (StackMutationOutcome) -> Void)?
    }

    private var document: StackDocument
    private let persistence: StorePersistence
    private let onChange: @MainActor @Sendable () -> Void
    private let diagnostics: DiagnosticSink

    private var queuedMutations: [QueuedMutation] = []
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var idleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public private(set) var error: StackStoreError?
    public private(set) var state: State = .idle

    public var stacks: [Stack] {
        document.stacks
    }

    public var currentStackID: StackSlot {
        document.currentStackID
    }

    public var selectedStackID: StackSlot {
        for queued in queuedMutations.reversed() {
            switch queued.mutation {
            case let .switchStack(id), let .moveNoteToStack(_, _, id): return id
            default: continue
            }
        }
        return document.currentStackID
    }

    public var currentStack: Stack {
        Stack(id: document.currentStackID, notes: document[document.currentStackID])
    }

    public func stack(id: StackSlot) -> Stack? {
        stacks.stack(id: id)
    }

    public var currentNotes: [Note] {
        currentStack.notes
    }

    public var lastCleared: ClearedBatch? {
        document.lastCleared
    }

    public var hasPendingMutations: Bool {
        !queuedMutations.isEmpty
    }

    public init(
        persistence: StorePersistence,
        onChange: @escaping @MainActor @Sendable () -> Void = {},
        diagnostics: @escaping DiagnosticSink = { _ in }
    ) async throws {
        try Task.checkCancellation()
        let loaded = try await persistence.load()
        try Task.checkCancellation()
        let initialDocument: StackDocument
        if let loaded {
            initialDocument = loaded
        } else {
            let candidate = StackDocument.empty()
            try Task.checkCancellation()
            try await persistence.commit(candidate)
            try Task.checkCancellation()
            initialDocument = candidate
        }

        self.document = initialDocument
        self.persistence = persistence
        self.onChange = onChange
        self.diagnostics = diagnostics
    }

    public func mutate(
        _ mutation: StackDocumentMutation,
        operationID: UUID = UUID(),
        outcome: (@MainActor @Sendable (StackMutationOutcome) -> Void)? = nil
    ) {
        guard state != .tornDown else {
            error = .tornDown
            outcome?(.cancelled)
            return
        }

        let queued = QueuedMutation(mutation: mutation, operationID: operationID, outcome: outcome)
        diagnose(queued, .accepted)
        queuedMutations.append(queued)
        startProcessingIfNeeded()
    }

    public func retryPendingMutations() {
        switch state {
        case .tornDown:
            error = .tornDown
        case .processing:
            break
        case .halted:
            state = .idle
            startProcessingIfNeeded()
        case .idle:
            startProcessingIfNeeded()
        }
    }

    public func waitForIdle() async {
        guard state == .processing else { return }
        let waiter = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                idleWaiters[waiter] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.idleWaiters.removeValue(forKey: waiter)?.resume() }
        }
    }

    public func drain(timeout: Duration) async {
        guard state == .processing else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.waitForIdle() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    public func teardown() {
        guard state != .tornDown else { return }
        state = .tornDown
        let abandoned = queuedMutations
        queuedMutations.removeAll()
        processingTask?.cancel()
        processingTask = nil
        abandoned.forEach { diagnose($0, .cancelled); $0.outcome?(.cancelled) }
        resumeIdleWaiters()
    }

    private func startProcessingIfNeeded() {
        guard state == .idle, hasPendingMutations else { return }
        state = .processing
        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        while state == .processing, !Task.isCancelled, let queuedMutation = queuedMutations.first {
            switch StackDocumentMutations.applying(queuedMutation.mutation, to: document) {
            case let .applied(candidate):
                switch await commit(candidate) {
                case .committed:
                    guard state == .processing, !Task.isCancelled else {
                        finishProcessing()
                        return
                    }
                    queuedMutations.removeFirst()
                    diagnose(queuedMutation, .succeeded)
                    queuedMutation.outcome?(.committed)
                case let .failed(message):
                    guard state != .tornDown else {
                        finishProcessing()
                        return
                    }
                    finishProcessing(nextState: .halted)
                    diagnose(queuedMutation, .failed)
                    queuedMutation.outcome?(.commitFailed(message))
                    onChange()
                    return
                case .cancelled:
                    finishProcessing()
                    return
                }
            case .noOp:
                queuedMutations.removeFirst()
                diagnose(queuedMutation, .succeeded)
                queuedMutation.outcome?(.noOp)
            case let .rejected(message):
                queuedMutations.removeFirst()
                diagnose(queuedMutation, .rejected)
                error = .mutationRejected(message)
                queuedMutation.outcome?(.rejected(message))
                onChange()
            }
        }

        finishProcessing()
    }

    private func commit(_ candidate: StackDocument) async -> CommitOutcome {
        do {
            try Task.checkCancellation()
            try await persistence.commit(candidate)
            try Task.checkCancellation()
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard state == .processing, !Task.isCancelled else { return .cancelled }
            let message = error.localizedDescription
            self.error = .commitFailed(message)
            return .failed(message)
        }

        guard state != .tornDown else { return .cancelled }
        document = candidate
        error = nil
        onChange()
        return .committed
    }

    private func finishProcessing(nextState: State = .idle) {
        guard state == .processing else { return }
        processingTask = nil
        state = nextState
        resumeIdleWaiters()
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters.values
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func diagnose(_ queued: QueuedMutation, _ outcome: DiagnosticRecord.Outcome) {
        switch queued.mutation {
        case let .addNote(stackID, note):
            diagnostics(DiagnosticRecord(.save, outcome, operationID: queued.operationID,
                                         stackID: stackID, noteID: note.id))
        case let .clearExportedNotes(stackID, notes):
            for note in notes {
                diagnostics(DiagnosticRecord(.cleanup, outcome, operationID: queued.operationID,
                                             stackID: stackID, noteID: note.id))
            }
        default: break
        }
    }
}
