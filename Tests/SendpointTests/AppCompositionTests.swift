import AppKit
import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class AppCompositionTests: XCTestCase {
    func testBootstrapTransitionsRejectWrongRequestsAndAreTerminalAfterTeardown() async throws {
        let request = UUID()
        let stale = UUID()
        let store = try await makeStore()
        defer { store.teardown() }
        var state = AppDelegate.StoreState.loading(request)
        XCTAssertFalse(state.update(.loaded(stale, store)))
        XCTAssertFalse(state.update(.failed(stale, "stale failure")))
        XCTAssertTrue(state.update(.loaded(request, store)))
        XCTAssertFalse(state.update(.begin(stale)))
        XCTAssertTrue(state.update(.teardown))
        XCTAssertFalse(state.update(.teardown))
        XCTAssertFalse(state.update(.begin(request)))
        XCTAssertFalse(state.update(.loaded(request, store)))
        XCTAssertFalse(state.update(.failed(request, "late failure")))
        guard case .tornDown = state else { return XCTFail("Shutdown must be terminal") }
    }

    func testBootstrapSuccessInstallsStoreBoundControllersAndChangeCallback() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        XCTAssertEqual(app.statusMenuStoreStatus, .loading)
        XCTAssertNil(app.palette)
        let store = try await makeStore(onChange: loader.callbacks[0])
        loader.succeed(0, store: store)
        await task.value
        XCTAssertTrue(app.store === store)
        XCTAssertEqual(app.statusMenuStoreStatus, .available)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertNotNil(app.palette)
        XCTAssertNotNil(app.latestNoteEditor)
        XCTAssertNotNil(app.stackSelector)
        XCTAssertNotNil(app.stackReadout)
        let context = CaptureIdentity(sourceStack: store.currentStackID)
        app.captureController.send(.begin(.typed(context)))
        app.captureController.send(.selection(context, CapturedSelection(text: "")))
        XCTAssertEqual(app.captureController.state.destination?.slot, store.currentStackID)
        store.select(store.stacks[1].id)
        await store.waitForIdle()
        XCTAssertEqual(store.currentStackID, store.stacks[1].id)
        XCTAssertEqual(app.captureController.state.destination?.slot, store.stacks[1].id)
        app.bootstrapStore()
        XCTAssertNil(app.bootstrapTask)
        XCTAssertEqual(loader.callbacks.count, 1)
    }

    func testBootstrapFailureLeavesStoreUnavailableAndRetryCanSucceed() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let failed = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        loader.fail(0, error: NSError(domain: "StoreLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bootstrap failed"]))
        await failed.value
        guard case let .unavailable(message) = app.storeState else { return XCTFail("Expected unavailable store") }
        XCTAssertTrue(message.contains("Bootstrap failed"))
        XCTAssertEqual(app.statusMenuStoreStatus, .unavailable(message))
        XCTAssertNil(app.store)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertNil(app.palette)
        XCTAssertNil(app.latestNoteEditor)
        app.bootstrapStore()
        let retry = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(2)
        let store = try await makeStore()
        loader.succeed(1, store: store)
        await retry.value
        XCTAssertTrue(app.store === store)
        XCTAssertEqual(app.statusMenuStoreStatus, .available)
    }

    func testCancelledBootstrapReleasesItsHandleWithoutPublishingFailure() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        task.cancel()
        loader.fail(0, error: CancellationError())
        await task.value
        XCTAssertNil(app.bootstrapTask)
        XCTAssertNil(app.store)
        XCTAssertEqual(app.statusMenuStoreStatus, .loading)
        XCTAssertNil(app.palette)
    }

    func testBootstrapCancelledBeforeStartingDoesNotCallLoader() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        task.cancel()
        await task.value
        XCTAssertTrue(loader.callbacks.isEmpty)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertNil(app.store)
        XCTAssertEqual(app.statusMenuStoreStatus, .loading)
    }

    func testCancelledBootstrapRejectsLateSuccessAndReleasesItsHandle() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        task.cancel()
        let store = try await makeStore()
        loader.succeed(0, store: store)
        await task.value
        XCTAssertEqual(store.state, .tornDown)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertNil(app.store)
        XCTAssertEqual(app.statusMenuStoreStatus, .loading)
    }

    func testReplacedBootstrapRejectsLateStoreWithoutClearingNewTask() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let old = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        app.bootstrapStore()
        let current = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(2)
        let staleStore = try await makeStore()
        loader.succeed(0, store: staleStore)
        await old.value
        XCTAssertTrue(old.isCancelled)
        XCTAssertEqual(staleStore.state, .tornDown)
        XCTAssertNotNil(app.bootstrapTask)
        XCTAssertEqual(app.statusMenuStoreStatus, .loading)
        XCTAssertNil(app.store)
        let currentStore = try await makeStore()
        loader.succeed(1, store: currentStore)
        await current.value
        XCTAssertTrue(app.store === currentStore)
        XCTAssertNil(app.bootstrapTask)
    }

    func testReplacedBootstrapLateFailureDoesNotOverwriteSuccess() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        defer { app.teardown() }
        app.bootstrapStore()
        let old = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        app.bootstrapStore()
        let current = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(2)
        let store = try await makeStore()
        loader.succeed(1, store: store)
        await current.value
        loader.fail(0, error: NSError(domain: "StoreLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stale failure"]))
        await old.value
        XCTAssertTrue(app.store === store)
        XCTAssertEqual(app.statusMenuStoreStatus, .available)
        XCTAssertNil(app.bootstrapTask)
    }

    func testShutdownCancelsBootstrapAndRejectsLateSuccessAndRestart() async throws {
        let loader = CompositionStoreLoader()
        let app = makeApp(loader: loader)
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        app.teardown()
        XCTAssertTrue(task.isCancelled)
        XCTAssertNil(app.bootstrapTask)
        let lateStore = try await makeStore()
        loader.succeed(0, store: lateStore)
        await task.value
        app.bootstrapStore()
        XCTAssertEqual(lateStore.state, .tornDown)
        XCTAssertNil(app.store)
        XCTAssertNil(app.palette)
        XCTAssertNil(app.latestNoteEditor)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertEqual(loader.callbacks.count, 1)
        guard case .tornDown = app.storeState else { return XCTFail("Shutdown must be terminal") }
        await app.environment.voiceService.waitForTeardown()
    }

    func testLatestEditorBlocksExportBeforeFakeClipboardThenClosedEditorExports() async throws {
        let loader = CompositionStoreLoader()
        var writes: [String] = []
        var pastes = 0
        let app = makeApp(loader: loader, exportServices: ExportServices(
            write: { writes.append($0); return writes.count },
            paste: { _, _ in pastes += 1; return true }
        ))
        defer { app.teardown() }
        let store = try await makeStore()
        app.bootstrapStore()
        let task = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        loader.succeed(0, store: store)
        await task.value
        let editor = try XCTUnwrap(app.latestNoteEditor?.model)
        editor.onPresent = {}
        editor.send(.open)
        let focus = editor.focusRequest
        let originalNotes = store.currentNotes
        app.perform(.copyMarkdown)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(app.exportController.state, .idle)
        XCTAssertEqual(editor.focusRequest, focus + 1)
        XCTAssertTrue(editor.isOpen)
        XCTAssertEqual(store.currentNotes, originalNotes)
        editor.send(.dismiss)
        XCTAssertFalse(editor.isOpen)
        app.perform(.copyMarkdown)
        XCTAssertEqual(writes, [PromptComposer.markdown(stack: store.currentStack, template: app.templateSettings.activeTemplate)])
        await store.waitForIdle()
        XCTAssertEqual(pastes, 0)
    }

    func testShutdownIsIdempotentAndCancelsOwnedTasksAndQueuedMutationOnce() async throws {
        let loader = CompositionStoreLoader()
        var writes = 0
        let app = makeApp(loader: loader, exportServices: ExportServices(
            write: { _ in writes += 1; return writes }, paste: { _, _ in false }
        ))
        app.bootstrapStore()
        let bootstrap = try XCTUnwrap(app.bootstrapTask)
        await loader.waitForCalls(1)
        let store = try await makeStore()
        loader.succeed(0, store: store)
        await bootstrap.value
        let editor = try XCTUnwrap(app.latestNoteEditor?.model)
        var outcomes: [StackMutationOutcome] = []
        store.mutate(.clearStack(stackID: store.currentStackID)) { outcomes.append($0) }
        let termination = Task { do { try await Task.sleep(for: .seconds(60)) } catch {} }
        app.terminationTask = termination
        app.teardown()
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        app.perform(.copyMarkdown)
        app.bootstrapStore()
        XCTAssertEqual(outcomes, [.cancelled])
        XCTAssertTrue(termination.isCancelled)
        XCTAssertNil(app.terminationTask)
        XCTAssertNil(app.bootstrapTask)
        XCTAssertEqual(store.state, .tornDown)
        XCTAssertEqual(editor.state, .tornDown)
        XCTAssertEqual(app.exportController.state, .tornDown)
        XCTAssertNil(app.palette)
        XCTAssertNil(app.latestNoteEditor)
        XCTAssertNil(app.stackSelector)
        XCTAssertNil(app.stackReadout)
        XCTAssertTrue(app.surfaces.visible.isEmpty)
        XCTAssertEqual(writes, 0)
        await termination.value
        await app.environment.voiceService.waitForTeardown()
    }

    private func makeApp(loader: CompositionStoreLoader, exportServices: ExportServices? = nil) -> AppDelegate {
        let defaults = UserDefaults(suiteName: "AppCompositionTests.\(UUID())")!
        return AppDelegate(environment: AppEnvironment(
            defaults: defaults,
            hotKeyCenter: HotKeyCenter(registerEvent: { _, _, _ in (-1, nil) }, unregisterEvent: { _ in }),
            exportServices: exportServices,
            selectionCapture: SelectionCapture(read: { _, _ in CapturedSelection(text: "") }, paste: { _, _ in false }),
            captureSurfaces: { _ in CaptureSurfaces(prepare: {}, show: { _ in }, focus: {}, close: {}, discard: {}) },
            loadStore: { try await loader.load(onChange: $0) }
        ))
    }

    private func makeStore(onChange: @escaping @MainActor @Sendable () -> Void = {}) async throws -> StackStore {
        let stacks = filled([Stack(notes: [Note(subject: .standalone, body: "Original")])])
        let document = StackDocument(stacks: stacks)
        return try await StackStore(
            persistence: StorePersistence(load: { document }, commit: { _ in }), onChange: onChange
        )
    }
}

@MainActor
private final class CompositionStoreLoader {
    var callbacks: [@MainActor @Sendable () -> Void] = []
    private var requests: [CheckedContinuation<StackStore, any Error>?] = []
    private let started = AsyncAcknowledgement()

    func load(onChange: @escaping @MainActor @Sendable () -> Void) async throws -> StackStore {
        try await withCheckedThrowingContinuation { continuation in
            callbacks.append(onChange)
            requests.append(continuation)
            started.signal()
        }
    }

    func waitForCalls(_ count: Int) async {
        await started.wait(for: count)
    }

    func succeed(_ request: Int, store: StackStore) {
        let continuation = requests[request]
        requests[request] = nil
        continuation?.resume(returning: store)
    }

    func fail(_ request: Int, error: any Error) {
        let continuation = requests[request]
        requests[request] = nil
        continuation?.resume(throwing: error)
    }
}
