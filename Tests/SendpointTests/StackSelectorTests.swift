import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StackSelectorTests: XCTestCase {
    @MainActor
    private final class Spy {
        var shown: [Int] = []
        var hidden = 0
        var showsReadout = true
    }

    @MainActor
    private final class ManualSleep: Sendable {
        private var waiters: [CheckedContinuation<Void, Error>] = []
        private(set) var started = 0

        func sleep(_: Duration) async throws {
            started += 1
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { waiters.append($0) }
            } onCancel: {
                Task { @MainActor in self.cancelAll() }
            }
        }

        func finishAll() {
            let resumed = waiters
            waiters = []
            resumed.forEach { $0.resume() }
        }

        private func cancelAll() {
            let resumed = waiters
            waiters = []
            resumed.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    func testAPressSwitchesShowsTheReadoutAndTheTimerTakesItDown() async throws {
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }))
        let spy = Spy()
        let clock = ManualSleep()
        let selector = makeSelector(store: store, spy: spy, clock: clock)

        selector.select(3)
        await store.waitForIdle()

        XCTAssertEqual(store.currentStackID, store.stacks[2].id)
        XCTAssertEqual(spy.shown, [3])
        XCTAssertEqual(spy.hidden, 0)

        await waitUntil { clock.started == 1 }
        clock.finishAll()
        await waitUntil { spy.hidden == 1 }
        selector.teardown()
        XCTAssertEqual(spy.hidden, 1, "an idle teardown has nothing to hide")
    }

    func testSwitchingBackBeforeTheFirstCommitLandsOnTheLatestPress() async throws {
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }))
        let spy = Spy()
        let selector = makeSelector(store: store, spy: spy, clock: ManualSleep())

        selector.select(2)
        selector.select(1)
        await store.waitForIdle()

        XCTAssertEqual(store.currentStackID, store.stacks[0].id)
        XCTAssertEqual(spy.shown, [2, 1])
        selector.teardown()
    }

    func testAFailedCommitTakesTheReadoutDownAndLeavesTheCurrentStack() async throws {
        let document = StackDocument.empty()
        let store = try await StackStore(persistence: StorePersistence(
            load: { document },
            commit: { _ in throw StorePersistenceError.unavailable }
        ))
        let spy = Spy()
        let selector = makeSelector(store: store, spy: spy, clock: ManualSleep())

        selector.select(2)
        await store.waitForIdle()

        XCTAssertEqual(store.currentStackID, document.currentStackID)
        XCTAssertEqual(spy.shown, [2])
        XCTAssertEqual(spy.hidden, 1)
        selector.teardown()
    }

    func testTeardownHidesTheReadoutCancelsItsTimerAndIgnoresLaterPresses() async throws {
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }))
        let spy = Spy()
        let clock = ManualSleep()
        let selector = makeSelector(store: store, spy: spy, clock: clock)

        selector.select(1)
        await waitUntil { clock.started == 1 }
        selector.teardown()
        selector.teardown()
        XCTAssertEqual(spy.hidden, 1)

        clock.finishAll()
        selector.select(4)
        await store.waitForIdle()
        XCTAssertEqual(spy.shown, [1])
        XCTAssertEqual(spy.hidden, 1)
        XCTAssertEqual(store.currentStackID, store.stacks[0].id)
    }

    func testNoReadoutWhileAnotherSurfaceNamesTheStack() async throws {
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }))
        let spy = Spy()
        spy.showsReadout = false
        let selector = makeSelector(store: store, spy: spy, clock: ManualSleep())

        selector.select(5)
        await store.waitForIdle()

        XCTAssertEqual(store.currentStackID, store.stacks[4].id)
        XCTAssertTrue(spy.shown.isEmpty)
        selector.teardown()
    }

    private func makeSelector(store: StackStore, spy: Spy, clock: ManualSleep) -> StackSelector {
        StackSelector(
            store: store,
            showsReadout: { spy.showsReadout },
            showReadout: { spy.shown.append($0) },
            hideReadout: { spy.hidden += 1 },
            sleep: { try await clock.sleep($0) }
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition())
    }
}
