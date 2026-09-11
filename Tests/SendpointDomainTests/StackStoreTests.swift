import Foundation
import XCTest
@testable import SendpointDomain

@MainActor
final class StackStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let stackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    func testLoadsExistingDocumentWithoutReplacingOrCommittingIt() async throws {
        let original = document(name: "Existing")
        let recorder = CommitRecorder()
        let persistence = StorePersistence(
            load: { original },
            commit: { document in await recorder.record(document) }
        )

        let store = try await StackStore(persistence: persistence)

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.currentStackID, stackID)
        XCTAssertEqual(store.currentStack, original.stacks[0])
        XCTAssertEqual(store.currentNotes, [])
        XCTAssertNil(store.lastCleared)
        let commits = await recorder.documents()
        XCTAssertEqual(commits, [])
    }

    func testFirstLoadCommitsDefaultBeforeStoreIsReturned() async throws {
        let recorder = CommitRecorder()
        let persistence = StorePersistence(
            load: { nil },
            commit: { document in await recorder.record(document) }
        )
        let defaultStack = Stack(id: stackID, name: "Default", createdAt: now)

        let store = try await StackStore(
            persistence: persistence,
            defaultStack: defaultStack
        )

        XCTAssertEqual(store.currentStack, defaultStack)
        let commits = await recorder.documents()
        XCTAssertEqual(commits, [
            StackDocument(stacks: [defaultStack], currentStackID: stackID)
        ])
    }

    func testCommitFailureRetainsFailedAndLaterMutationsUntilExplicitRetry() async throws {
        let original = document()
        let recorder = AttemptRecorder(failingAttempts: [1])
        let persistence = StorePersistence(
            load: { original },
            commit: { document in try await recorder.commit(document) }
        )
        var callbackCount = 0
        let store = try await StackStore(persistence: persistence) {
            callbackCount += 1
        }
        let first = makeNote(body: "first")
        let second = makeNote(body: "second")
        var outcomeEvents: [MutationOutcomeEvent] = []

        store.mutate(.addNote(stackID: stackID, note: first), outcome: {
            outcomeEvents.append(MutationOutcomeEvent(mutation: "first", outcome: $0))
        })
        store.mutate(.addNote(stackID: stackID, note: second), outcome: {
            outcomeEvents.append(MutationOutcomeEvent(mutation: "second", outcome: $0))
        })
        await store.waitForIdle()

        XCTAssertEqual(outcomeEvents, [
            MutationOutcomeEvent(mutation: "first", outcome: .commitFailed("failed")),
        ])
        XCTAssertEqual(store.currentNotes, [])
        XCTAssertEqual(store.state, .halted)
        XCTAssertEqual(store.error, .commitFailed("failed"))
        XCTAssertTrue(store.hasPendingMutations)
        XCTAssertEqual(callbackCount, 0)
        var attempts = await recorder.documents()
        XCTAssertEqual(attempts.map { $0.stacks[0].notes.map(\.body) }, [["first"]])

        store.retryPendingMutations()
        XCTAssertEqual(store.state, .processing)
        await store.waitForIdle()
        XCTAssertEqual(store.state, .idle)

        XCTAssertEqual(outcomeEvents, [
            MutationOutcomeEvent(mutation: "first", outcome: .commitFailed("failed")),
            MutationOutcomeEvent(mutation: "first", outcome: .committed),
            MutationOutcomeEvent(mutation: "second", outcome: .committed),
        ])
        XCTAssertEqual(store.currentNotes, [first, second])
        XCTAssertNil(store.error)
        XCTAssertFalse(store.hasPendingMutations)
        XCTAssertEqual(callbackCount, 2)
        attempts = await recorder.documents()
        XCTAssertEqual(attempts.map { $0.stacks[0].notes.map(\.body) }, [
            ["first"],
            ["first"],
            ["first", "second"],
        ])
    }

    func testDeleteThenAddToDeletedStackRejectsInQueueOrder() async throws {
        let first = document(name: "First").stacks[0]
        let second = Stack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            name: "Second",
            createdAt: now
        )
        let original = StackDocument(
            stacks: [first, second],
            currentStackID: first.id
        )
        let recorder = CommitRecorder()
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { document in await recorder.record(document) }
        ))
        var outcomes: [StackMutationOutcome] = []

        store.mutate(.deleteStack(stackID: first.id), outcome: { outcomes.append($0) })
        store.mutate(
            .addNote(stackID: first.id, note: makeNote(body: "too late")),
            outcome: { outcomes.append($0) }
        )
        await store.waitForIdle()

        XCTAssertEqual(outcomes, [
            .committed,
            .rejected("The target stack no longer exists."),
        ])
        XCTAssertEqual(store.stacks, [second])
        XCTAssertEqual(store.error, .mutationRejected("The target stack no longer exists."))
        let commits = await recorder.documents()
        XCTAssertEqual(commits.count, 1)
    }

    func testNoOpOutcomeFiresOnceAfterMutationIsRemoved() async throws {
        let original = document()
        let recorder = CommitRecorder()
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { document in await recorder.record(document) }
        ))
        var outcomes: [StackMutationOutcome] = []
        var pendingStates: [Bool] = []

        store.mutate(.switchStack(stackID: stackID), outcome: { outcome in
            outcomes.append(outcome)
            pendingStates.append(store.hasPendingMutations)
        })
        await store.waitForIdle()

        XCTAssertEqual(outcomes, [.noOp])
        XCTAssertEqual(pendingStates, [false])
        let commits = await recorder.documents()
        XCTAssertEqual(commits, [])
    }

    func testRapidMutationsCommitInOrderWithoutLostUpdates() async throws {
        let original = document()
        let recorder = CommitRecorder(delayNanoseconds: 5_000_000)
        let persistence = StorePersistence(
            load: { original },
            commit: { document in try await recorder.recordAfterDelay(document) }
        )
        let store = try await StackStore(persistence: persistence)
        let notes = [makeNote(body: "one"), makeNote(body: "two"), makeNote(body: "three")]

        for note in notes {
            store.mutate(.addNote(stackID: stackID, note: note))
        }
        await store.waitForIdle()

        XCTAssertEqual(store.currentNotes, notes)
        let commits = await recorder.documents()
        XCTAssertEqual(commits.map { $0.stacks[0].notes.map(\.body) }, [
            ["one"],
            ["one", "two"],
            ["one", "two", "three"],
        ])
        let maximumInFlightCommitCount = await recorder.maximumInFlightCommitCount()
        XCTAssertEqual(maximumInFlightCommitCount, 1)
    }

    func testCallbackRunsOnlyAfterCommitAndPublishedStateIsVisible() async throws {
        let original = document()
        let commitStarted = expectation(description: "commit started")
        let gate = AsyncGate()
        let persistence = StorePersistence(
            load: { original },
            commit: { _ in
                commitStarted.fulfill()
                await gate.wait()
            }
        )
        var callbackSnapshots: [[Note]] = []
        var store: StackStore!
        store = try await StackStore(persistence: persistence) {
            callbackSnapshots.append(store.currentNotes)
        }
        let added = makeNote(body: "committed")

        store.mutate(.addNote(stackID: stackID, note: added))
        await fulfillment(of: [commitStarted], timeout: 1)
        XCTAssertEqual(store.state, .processing)
        store.retryPendingMutations()
        XCTAssertEqual(store.state, .processing)
        XCTAssertEqual(store.currentNotes, [])
        XCTAssertEqual(callbackSnapshots, [])

        await gate.open()
        await store.waitForIdle()
        XCTAssertEqual(store.currentNotes, [added])
        XCTAssertEqual(callbackSnapshots, [[added]])
        XCTAssertEqual(store.state, .idle)
    }

    func testClearBeforeLateProvenanceThenUndoRestoresEnrichment() async throws {
        let original = document()
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { _ in }
        ))
        let base = makeNote(body: "Keep")
        let enriched = Provenance(
            application: base.provenance.application,
            windowTitle: "Focused window"
        )

        store.mutate(.addNote(stackID: stackID, note: base))
        store.mutate(.clearStack(stackID: stackID))
        store.mutate(.updateNoteProvenance(
            stackID: stackID,
            noteID: base.id,
            expectedApplication: base.provenance.application,
            provenance: enriched
        ))
        store.mutate(.undoClear)
        await store.waitForIdle()

        XCTAssertEqual(store.currentNotes.count, 1)
        XCTAssertEqual(store.currentNotes.first?.id, base.id)
        XCTAssertEqual(store.currentNotes.first?.provenance, enriched)
        store.teardown()
    }

    func testTeardownReleasesWaitersWhenPersistenceIgnoresCancellation() async throws {
        let original = document()
        let commitStarted = expectation(description: "commit started")
        let commitReturned = expectation(description: "commit returned")
        let attempts = CommitAttemptCounter()
        let gate = AsyncGate()
        let persistence = StorePersistence(
            load: { original },
            commit: { _ in
                _ = await attempts.begin()
                commitStarted.fulfill()
                await gate.wait()
                commitReturned.fulfill()
            }
        )
        var callbackCount = 0
        var outcomeEvents: [MutationOutcomeEvent] = []
        let store = try await StackStore(persistence: persistence) {
            callbackCount += 1
        }

        store.mutate(
            .addNote(stackID: stackID, note: makeNote(body: "in flight")),
            outcome: { outcomeEvents.append(MutationOutcomeEvent(mutation: "active", outcome: $0)) }
        )
        await fulfillment(of: [commitStarted], timeout: 1)
        store.mutate(
            .addNote(stackID: stackID, note: makeNote(body: "queued")),
            outcome: { outcomeEvents.append(MutationOutcomeEvent(mutation: "queued", outcome: $0)) }
        )
        let idleWaiter = Task { await store.waitForIdle() }
        await Task.yield()

        store.teardown()
        store.teardown()
        await idleWaiter.value

        XCTAssertEqual(outcomeEvents, [
            MutationOutcomeEvent(mutation: "active", outcome: .cancelled),
            MutationOutcomeEvent(mutation: "queued", outcome: .cancelled),
        ])
        XCTAssertEqual(store.state, .tornDown)
        XCTAssertFalse(store.hasPendingMutations)
        XCTAssertEqual(store.currentNotes, [])
        XCTAssertEqual(callbackCount, 0)
        var commitAttemptCount = await attempts.count()
        XCTAssertEqual(commitAttemptCount, 1)

        store.mutate(.addNote(stackID: stackID, note: makeNote(body: "late")))
        XCTAssertEqual(store.error, .tornDown)

        await gate.open()
        await fulfillment(of: [commitReturned], timeout: 1)
        commitAttemptCount = await attempts.count()
        XCTAssertEqual(commitAttemptCount, 1)
        XCTAssertEqual(outcomeEvents, [
            MutationOutcomeEvent(mutation: "active", outcome: .cancelled),
            MutationOutcomeEvent(mutation: "queued", outcome: .cancelled),
        ])
        XCTAssertEqual(store.currentNotes, [])
        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(store.state, .tornDown)
        store.retryPendingMutations()
        XCTAssertEqual(store.state, .tornDown)
    }

    func testFailureCallbackCanRetryAfterObservingHaltedState() async throws {
        let original = document()
        let recorder = AttemptRecorder(failingAttempts: [1])
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { try await recorder.commit($0) }
        ))
        let completed = expectation(description: "retry committed")
        var states: [StackStore.State] = []
        var outcomes: [StackMutationOutcome] = []
        let added = makeNote(body: "retry from callback")
        store.mutate(.addNote(stackID: stackID, note: added)) { outcome in
            states.append(store.state)
            outcomes.append(outcome)
            if case .commitFailed = outcome {
                store.retryPendingMutations()
                XCTAssertEqual(store.state, .processing)
            } else if outcome == .committed {
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 1)
        await store.waitForIdle()
        XCTAssertEqual(states, [.halted, .processing])
        XCTAssertEqual(outcomes, [.commitFailed("failed"), .committed])
        XCTAssertEqual(store.currentNotes, [added])
        XCTAssertEqual(store.state, .idle)
        let attempts = await recorder.documents()
        XCTAssertEqual(attempts.count, 2)
    }

    func testEnqueueWhileHaltedWaitsForRetryAndTeardownIsTerminal() async throws {
        let original = document()
        let recorder = AttemptRecorder(failingAttempts: [1])
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { try await recorder.commit($0) }
        ))
        var outcomes: [StackMutationOutcome] = []
        store.mutate(.renameStack(stackID: stackID, name: "Failed")) { outcomes.append($0) }
        await store.waitForIdle()
        store.mutate(.renameStack(stackID: stackID, name: "Queued")) { outcomes.append($0) }
        await store.waitForIdle()
        XCTAssertEqual(store.state, .halted)
        let attempts = await recorder.documents()
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(store.currentStack.name, "First")
        store.teardown()
        store.teardown()
        store.retryPendingMutations()
        XCTAssertEqual(store.state, .tornDown)
        XCTAssertFalse(store.hasPendingMutations)
        XCTAssertEqual(outcomes, [.commitFailed("failed"), .cancelled, .cancelled])
    }

    func testDrainReturnsOnceAQueuedCommitLands() async throws {
        let original = document()
        let gate = AsyncGate()
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { _ in await gate.wait() }
        ))
        let added = makeNote(body: "queued at quit")

        store.mutate(.addNote(stackID: stackID, note: added))
        let drain = Task { await store.drain(timeout: .seconds(5)) }
        await Task.yield()
        XCTAssertEqual(store.state, .processing)

        await gate.open()
        await drain.value

        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.currentNotes, [added])
    }

    func testDrainGivesUpAfterTheTimeoutAndLeavesTheStoreProcessing() async throws {
        let original = document()
        let gate = AsyncGate()
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { _ in await gate.wait() }
        ))

        store.mutate(.addNote(stackID: stackID, note: makeNote(body: "slow")))
        await store.drain(timeout: .milliseconds(20))

        XCTAssertEqual(store.state, .processing)
        XCTAssertEqual(store.currentNotes, [])
        await gate.open()
        await store.waitForIdle()
        XCTAssertEqual(store.currentNotes.count, 1)
    }

    func testDrainReturnsAtOnceForAnIdleOrHaltedStore() async throws {
        let original = document()
        let recorder = AttemptRecorder(failingAttempts: [1])
        let store = try await StackStore(persistence: StorePersistence(
            load: { original },
            commit: { try await recorder.commit($0) }
        ))
        await store.drain(timeout: .seconds(5))
        XCTAssertEqual(store.state, .idle)

        store.mutate(.renameStack(stackID: stackID, name: "Fails"))
        await store.waitForIdle()
        XCTAssertEqual(store.state, .halted)
        await store.drain(timeout: .seconds(5))
        XCTAssertEqual(store.state, .halted)
    }

    func testCancelledLoadCannotReturnAnActiveStore() async {
        let original = document()
        let task = Task {
            try await StackStore(persistence: StorePersistence(
                load: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return original
                },
                commit: { _ in XCTFail("Cancelled load must not commit") }
            ))
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func document(name: String = "First") -> StackDocument {
        StackDocument(
            stacks: [Stack(id: stackID, name: name, createdAt: now)],
            currentStackID: stackID
        )
    }

    private func makeNote(body: String) -> Note {
        Note(
            subject: .standalone,
            body: body,
            provenance: Provenance(application: ApplicationIdentity(name: "Tests")),
            createdAt: now
        )
    }
}

private struct MutationOutcomeEvent: Equatable {
    let mutation: String
    let outcome: StackMutationOutcome
}

private enum TestFailure: LocalizedError, CustomStringConvertible {
    case failed

    var description: String { "failed" }
    var errorDescription: String? { description }
}

private actor AttemptRecorder {
    private let failingAttempts: Set<Int>
    private var attemptedDocuments: [StackDocument] = []

    init(failingAttempts: Set<Int>) {
        self.failingAttempts = failingAttempts
    }

    func commit(_ document: StackDocument) throws {
        attemptedDocuments.append(document)
        if failingAttempts.contains(attemptedDocuments.count) {
            throw TestFailure.failed
        }
    }

    func documents() -> [StackDocument] {
        attemptedDocuments
    }
}

private actor CommitRecorder {
    private var committed: [StackDocument] = []
    private var inFlightCommitCount = 0
    private var maximumInFlightCount = 0
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func record(_ document: StackDocument) {
        committed.append(document)
    }

    func recordAfterDelay(_ document: StackDocument) async throws {
        inFlightCommitCount += 1
        maximumInFlightCount = max(maximumInFlightCount, inFlightCommitCount)
        defer { inFlightCommitCount -= 1 }
        try await Task.sleep(nanoseconds: delayNanoseconds)
        committed.append(document)
    }

    func documents() -> [StackDocument] {
        committed
    }

    func maximumInFlightCommitCount() -> Int {
        maximumInFlightCount
    }
}

private actor CommitAttemptCounter {
    private var value = 0

    func begin() -> Int {
        value += 1
        return value
    }

    func count() -> Int {
        value
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}
