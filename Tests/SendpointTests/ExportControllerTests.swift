import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class ExportControllerTests: XCTestCase {
    func testEveryBuiltInPastesItsPromptAndClearsWithoutOverridingDefaults() async throws {
        for template in Template.builtIns {
            let stack = Stack(notes: [note])
            let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
            let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
            defer { store.teardown() }
            var written = ""
            let reported = expectation(description: "\(template.name) pasted")
            let exporter = ExportController(services: ExportServices(
                write: { written = $0; return 42 },
                paste: { pid, revision in
                    XCTAssertEqual(pid, 1)
                    XCTAssertEqual(revision, 42)
                    return true
                }
            ))
            defer { exporter.teardown() }

            exporter.copy(store: store, stackID: stack.id, template: template, pasteTarget: 1) { _ in
                reported.fulfill()
            }
            await fulfillment(of: [reported], timeout: 2)
            await store.waitForIdle()

            XCTAssertEqual(written, PromptComposer.markdown(stack: stack, template: template))
            XCTAssertEqual(exporter.state, .idle)
            XCTAssertTrue(store.currentNotes.isEmpty, template.name)
            XCTAssertEqual(store.lastCleared?.notes, [note])
        }
    }

    private let note = Note(
        subject: .standalone,
        body: "A note"
    )

    func testRejectedRequestDoesNotReplaceRetryStoreOrReporter() async throws {
        let stackA = Stack(notes: [note])
        let stackB = Stack(notes: [Note(subject: .standalone, body: "B")])
        let commits = FailingExportCommit()
        let storeA = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: filled([stackA]), currentStackID: stackA.id) },
            commit: { _ in try await commits.commit() }
        ))
        let storeB = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: filled([stackB]), currentStackID: stackB.id) },
            commit: { _ in XCTFail("Rejected B must not be committed") }
        ))
        defer { storeA.teardown(); storeB.teardown() }
        var template = Template.plain
        template.clearStackAfterExport = true
        var reportsA: [String] = []
        var reportsB: [String] = []
        let exporter = ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in false }))
        exporter.copy(store: storeA, stackID: stackA.id, template: template) { reportsA.append($0) }
        await storeA.waitForIdle()
        guard case .failed(_, _, true) = exporter.state else { return XCTFail("Expected retryable cleanup") }
        exporter.copy(store: storeB, stackID: stackB.id, template: template) { reportsB.append($0) }
        XCTAssertEqual(reportsB, ["Finish or retry the pending export first."])
        exporter.send(.retry)
        await storeA.waitForIdle()
        XCTAssertEqual(exporter.state, .idle)
        XCTAssertTrue(storeA.currentNotes.isEmpty)
        XCTAssertEqual(storeB.currentNotes, stackB.notes)
        XCTAssertEqual(reportsA.count, 2)
        let count = await commits.count
        XCTAssertEqual(count, 2)
    }

    func testReentrantRejectedRequestCannotRedirectSnapshotClear() async throws {
        let stackA = Stack(notes: [note])
        let stackB = Stack(notes: [Note(subject: .standalone, body: "B")])
        let storeA = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: filled([stackA]), currentStackID: stackA.id) }, commit: { _ in }
        ))
        let storeB = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: filled([stackB]), currentStackID: stackB.id) }, commit: { _ in }
        ))
        defer { storeA.teardown(); storeB.teardown() }
        var template = Template.plain
        template.clearStackAfterExport = true
        let exporter = ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in false }))
        var reportsB: [String] = []
        exporter.copy(store: storeA, stackID: stackA.id, template: template) { _ in
            exporter.copy(store: storeB, stackID: stackB.id, template: template) { reportsB.append($0) }
        }
        await storeA.waitForIdle()
        await storeB.waitForIdle()
        XCTAssertEqual(exporter.state, .idle)
        XCTAssertTrue(storeA.currentNotes.isEmpty)
        XCTAssertEqual(storeB.currentNotes, stackB.notes)
        XCTAssertEqual(reportsB, ["Finish or retry the pending export first."])
    }

    func testClipboardWriteFailureDoesNotClear() async throws {
        let stack = Stack(notes: [note])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(
            persistence: StorePersistence(load: { document }, commit: { _ in })
        )
        var template = Template.plain
        template.clearStackAfterExport = true
        var attemptedText = ""
        let exporter = ExportController(services: ExportServices(
            write: { text in attemptedText = text; return nil },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, stackID: stack.id, template: template) { _ in }
        await store.waitForIdle()

        if case .failed = exporter.state {} else { XCTFail("Expected clipboard failure") }
        XCTAssertFalse(attemptedText.isEmpty)
        XCTAssertEqual(store.currentNotes, [note])
        store.teardown()
    }

    func testPasteCompletionClearsOnlyUnchangedExportedSnapshot() async throws {
        let unchanged = Note(subject: .standalone, body: "unchanged")
        let stack = Stack(notes: [note, unchanged])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        let gate = ExportPasteGate()
        let reported = expectation(description: "paste reported")
        var template = Template.plain
        template.clearStackAfterExport = true
        let exporter = ExportController(services: ExportServices(write: { _ in 42 }, paste: { _, revision in
            XCTAssertEqual(revision, 42)
            return await gate.run()
        }))
        defer { exporter.teardown(); gate.finish(false) }
        exporter.copy(store: store, stackID: stack.id, template: template, pasteTarget: 1) { _ in reported.fulfill() }
        await fulfillment(of: [gate.started], timeout: 2)
        let added = Note(subject: .standalone, body: "new")
        store.mutate(.updateNoteBody(stackID: stack.id, noteID: note.id, body: "edited"))
        store.mutate(.addNote(stackID: stack.id, note: added))
        await store.waitForIdle()
        gate.finish(true)
        await fulfillment(of: [reported], timeout: 2)
        await store.waitForIdle()
        XCTAssertEqual(exporter.state, .idle)
        XCTAssertEqual(store.currentNotes.map(\.body), ["edited", "new"])
        XCTAssertEqual(store.lastCleared?.notes, [unchanged])
    }

    func testBoundaryCancellationKeepsNotesAndFinishesTheAcceptedRequest() async throws {
        let stack = Stack(notes: [note])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        let reported = expectation(description: "cancelled paste reported")
        var template = Template.plain
        template.clearStackAfterExport = true
        let exporter = ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in
            throw CancellationError()
        }))
        exporter.copy(store: store, stackID: stack.id, template: template, pasteTarget: 1) { _ in reported.fulfill() }
        await fulfillment(of: [reported], timeout: 2)
        guard case .failed(_, _, false) = exporter.state else { return XCTFail("Cancelled boundary must finish") }
        XCTAssertEqual(store.currentNotes, [note])
        exporter.teardown()
    }

    func testSupersededAndTornDownPasteCannotApplyStaleResults() async throws {
        let stack = Stack(notes: [note])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        let first = ExportPasteGate()
        let second = ExportPasteGate()
        let exporter = ExportController(services: ExportServices(write: { _ in 1 }, paste: { pid, _ in
            await (pid == 1 ? first : second).run()
        }))
        defer { first.finish(false); second.finish(false) }
        var reports: [String] = []
        exporter.copy(store: store, stackID: stack.id, template: .plain, pasteTarget: 1) { reports.append($0) }
        await fulfillment(of: [first.started], timeout: 2)
        let firstTask = try XCTUnwrap(exporter.pasteTask?.task)
        exporter.copy(store: store, stackID: stack.id, template: .plain, pasteTarget: 2) { reports.append($0) }
        await fulfillment(of: [second.started], timeout: 2)
        let secondTask = try XCTUnwrap(exporter.pasteTask?.task)
        let current = exporter.state
        guard case let .awaitingPaste(currentRequest, _) = current else { return XCTFail("Expected second paste") }
        first.finish(true)
        await firstTask.value
        XCTAssertEqual(exporter.state, current)
        XCTAssertEqual(exporter.pasteTask?.requestID, currentRequest.id)
        XCTAssertTrue(reports.isEmpty)
        exporter.teardown()
        exporter.teardown()
        second.finish(true)
        await secondTask.value
        exporter.copy(store: store, stackID: stack.id, template: .plain) { reports.append($0) }
        XCTAssertEqual(exporter.state, .tornDown)
        XCTAssertTrue(reports.isEmpty)
        XCTAssertEqual(store.currentNotes, [note])
    }

    func testReentrantTeardownDuringNoteCopyCancellationCannotWriteClipboard() async throws {
        let stack = Stack(notes: [note])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        defer { store.teardown() }
        let gate = ExportPasteGate()
        var writes = 0
        var noteReports: [String] = []
        let exporter = ExportController(services: ExportServices(write: { _ in writes += 1; return writes },
                                                                  paste: { _, _ in await gate.run() }))
        exporter.copy(store: store, stackID: stack.id, template: .plain, pasteTarget: 1) { _ in exporter.teardown() }
        await fulfillment(of: [gate.started], timeout: 2)
        let task = try XCTUnwrap(exporter.pasteTask?.task)
        exporter.copyNote(note) { noteReports.append($0) }
        gate.finish(true)
        await task.value
        XCTAssertEqual(exporter.state, .tornDown)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(noteReports.isEmpty)
    }

    func testSuccessfulWriteUsesTheTemplateAndClearsTheStack() async throws {
        let stack = Stack(notes: [note])
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(
            persistence: StorePersistence(load: { document }, commit: { _ in })
        )
        var template = Template.plain
        template.preamble = "Use this template"
        template.clearStackAfterExport = true
        var written = ""
        let exporter = ExportController(services: ExportServices(
            write: { markdown in written = markdown; return 1 },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, stackID: stack.id, template: template) { _ in }
        await store.waitForIdle()

        XCTAssertEqual(exporter.state, .idle)
        XCTAssertEqual(written, "Use this template\n\nA note")
        XCTAssertTrue(store.currentNotes.isEmpty)
        XCTAssertEqual(store.lastCleared?.notes, [note])
        store.teardown()
    }
}

private actor FailingExportCommit {
    private(set) var count = 0
    func commit() throws {
        count += 1
        if count == 1 { throw StorePersistenceError.unavailable }
    }
}

@MainActor
private final class ExportPasteGate {
    let started = XCTestExpectation(description: "paste started")
    private var continuation: CheckedContinuation<Bool, Never>?
    func run() async -> Bool {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }
    func finish(_ result: Bool) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}
