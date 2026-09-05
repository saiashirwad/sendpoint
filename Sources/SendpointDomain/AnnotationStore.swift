import Foundation
import Observation

/// A failure from a queued annotation-store transition.
public enum AnnotationStoreError: Error, Equatable, Sendable {
    case mutationRejected(String)
    case commitFailed(String)
    case tornDown
}

/// The result reported for one queued mutation attempt.
public enum AnnotationStoreMutationOutcome: Equatable, Sendable {
    case committed
    case noOp
    case rejected(String)
    case commitFailed(String)
    case cancelled
}

/// Owns the last committed session document and serializes all changes to it.
@MainActor
@Observable
public final class AnnotationStore {
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
        let mutation: SessionDocumentMutation
        let outcome: (@MainActor @Sendable (AnnotationStoreMutationOutcome) -> Void)?
    }

    private var document: StoreDocument
    private let persistence: StorePersistence
    private let onChange: @MainActor @Sendable () -> Void

    private var queuedMutations: [QueuedMutation] = []
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public private(set) var error: AnnotationStoreError?
    public private(set) var state: State = .idle

    public var sessions: [Session] {
        document.sessions
    }

    public var currentSessionID: UUID {
        document.currentSessionID
    }

    public var currentSession: Session {
        // StoreDocument validation guarantees this lookup succeeds.
        document.sessions.first { $0.id == document.currentSessionID }!
    }

    public var currentEntries: [Annotation] {
        currentSession.entries
    }

    public var lastCleared: ClearedBatch? {
        document.lastCleared
    }

    public var hasPendingMutations: Bool {
        !queuedMutations.isEmpty
    }

    /// Loads the committed document. On first launch it commits `Default`
    /// before making the store available to its caller.
    public init(
        persistence: StorePersistence,
        defaultSession: Session = Session(name: "Default"),
        onChange: @escaping @MainActor @Sendable () -> Void = {}
    ) async throws {
        try Task.checkCancellation()
        let loaded = try await persistence.load()
        try Task.checkCancellation()
        let initialDocument: StoreDocument
        if let loaded {
            try SessionDocumentMutations.validate(loaded)
            initialDocument = loaded
        } else {
            let candidate = StoreDocument(
                sessions: [defaultSession],
                currentSessionID: defaultSession.id
            )
            try SessionDocumentMutations.validate(candidate)
            try Task.checkCancellation()
            try await persistence.commit(candidate)
            try Task.checkCancellation()
            initialDocument = candidate
        }

        self.document = initialDocument
        self.persistence = persistence
        self.onChange = onChange
    }

    /// Enqueues one pure document transition. The next candidate always starts
    /// from the last document whose commit completed successfully.
    public func mutate(
        _ mutation: SessionDocumentMutation,
        outcome: (@MainActor @Sendable (AnnotationStoreMutationOutcome) -> Void)? = nil
    ) {
        guard state != .tornDown else {
            error = .tornDown
            outcome?(.cancelled)
            return
        }

        queuedMutations.append(QueuedMutation(mutation: mutation, outcome: outcome))
        startProcessingIfNeeded()
    }

    /// Resumes work retained after a commit failure.
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

    /// Returns when the active drain completes or halts.
    public func waitForIdle() async {
        guard state == .processing else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    /// Stops accepting changes, discards queued work, and cancels
    /// the one task owned by the store. Repeated calls have no further effect.
    public func teardown() {
        guard state != .tornDown else { return }
        state = .tornDown
        let outcomes = queuedMutations.compactMap(\.outcome)
        queuedMutations.removeAll()
        processingTask?.cancel()
        processingTask = nil
        outcomes.forEach { $0(.cancelled) }
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
            switch SessionDocumentMutations.applying(queuedMutation.mutation, to: document) {
            case let .applied(candidate):
                switch await commit(candidate) {
                case .committed:
                    guard state == .processing, !Task.isCancelled else {
                        finishProcessing()
                        return
                    }
                    queuedMutations.removeFirst()
                    queuedMutation.outcome?(.committed)
                case let .failed(message):
                    guard state != .tornDown else {
                        finishProcessing()
                        return
                    }
                    // Release the failed drain before calling client code so
                    // a retry from the callback can own a new processing task.
                    finishProcessing(nextState: .halted)
                    queuedMutation.outcome?(.commitFailed(message))
                    return
                case .cancelled:
                    finishProcessing()
                    return
                }
            case .noOp:
                queuedMutations.removeFirst()
                queuedMutation.outcome?(.noOp)
            case let .rejected(message):
                queuedMutations.removeFirst()
                error = .mutationRejected(message)
                queuedMutation.outcome?(.rejected(message))
            }
        }

        finishProcessing()
    }

    private func commit(_ candidate: StoreDocument) async -> CommitOutcome {
        do {
            try Task.checkCancellation()
            try await persistence.commit(candidate)
            try Task.checkCancellation()
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard state == .processing, !Task.isCancelled else { return .cancelled }
            let message = String(describing: error)
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
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
