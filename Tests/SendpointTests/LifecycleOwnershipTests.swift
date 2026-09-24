import XCTest
@testable import Sendpoint

@MainActor
final class NoteFramesDisarmTests: XCTestCase {
    func testDisarmClearsLandingSoSettleNoOps() {
        let frames = NoteFrames()
        let id = UUID()
        frames.frames[id] = CGRect(x: 0, y: 0, width: 100, height: 100)

        frames.land(on: id)
        XCTAssertEqual(frames.landing, id)

        frames.disarm()
        XCTAssertNil(frames.landing)

        frames.settle()
        XCTAssertNil(frames.landing)
        XCTAssertEqual(frames.frames[id], CGRect(x: 0, y: 0, width: 100, height: 100), "disarm clears the landing, never the frames")
    }

    func testDisarmIsIdempotent() {
        let frames = NoteFrames()
        frames.disarm()
        frames.disarm()
        XCTAssertNil(frames.landing)
    }

    func testLateSettleRetryAfterDisarmNoOps() async {
        let frames = NoteFrames()
        let id = UUID()
        frames.frames[id] = CGRect(x: 0, y: 400, width: 100, height: 100)

        frames.land(on: id)
        frames.disarm()

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(frames.landing)
    }
}

@MainActor
final class VoiceModelWatchOwnershipTests: XCTestCase {
    private func services(
        modelFilesExist: (@Sendable () -> Bool)? = nil,
        downloadModel: @escaping @Sendable (
            _ onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void = { _ in }
    ) -> PermissionServices {
        PermissionServices(
            accessibilityStatus: { .granted },
            requestAccessibility: { true },
            microphoneStatus: { .granted },
            requestMicrophone: { true },
            voiceModelFilesExist: modelFilesExist ?? { true },
            downloadVoiceModel: downloadModel,
            openAccessibilitySettings: {},
            openMicrophoneSettings: {}
        )
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test work")
    }

    func testRedundantStartsShareOneLoopAndOneStopEndsIt() async {
        let files = LockedBool(false)
        let state = PermissionState(services: services(
            modelFilesExist: { files.value }
        ))
        XCTAssertFalse(state.isWatchingVoiceModel)

        state.startWatchingVoiceModel(interval: .milliseconds(5))
        state.startWatchingVoiceModel(interval: .milliseconds(5))
        XCTAssertTrue(state.isWatchingVoiceModel)

        files.value = true
        await waitUntil { state.localVoiceModel == .ready }

        state.stopWatchingVoiceModel()
        state.stopWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel)

        files.value = false
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(state.localVoiceModel, .ready, "no loop is left to pick up the removal")
        state.teardown()
    }

    func testStopWatchingIsNarrowerThanTeardown() async {
        let state = PermissionState(services: services(
            modelFilesExist: { false },
            downloadModel: { _ in try? await Task.sleep(for: .milliseconds(50)) }
        ))

        state.downloadModel()
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))

        state.startWatchingVoiceModel(interval: .milliseconds(5))
        XCTAssertTrue(state.isWatchingVoiceModel)
        state.stopWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel)
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil), "releasing the poll leaves the download alone")

        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testTeardownStopsTheWatchAndIgnoresUnbalancedStops() {
        let state = PermissionState(services: services())
        state.startWatchingVoiceModel()
        XCTAssertTrue(state.isWatchingVoiceModel)

        state.teardown()
        XCTAssertFalse(state.isWatchingVoiceModel)

        state.startWatchingVoiceModel()
        XCTAssertFalse(state.isWatchingVoiceModel, "no watch starts after teardown")
        state.stopWatchingVoiceModel()
        state.teardown()
    }
}

@MainActor
final class MicrophonePreviewOwnerTests: XCTestCase {
    private actor StartGate {
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private final class Recorder {
        var startedUIDs: [String?] = []
        var stopCount = 0
        var running = false
    }

    private func makeOwner(
        recorder: Recorder,
        gatedUIDs: Set<String> = [],
        gate: StartGate
    ) -> MicrophonePreviewOwner {
        MicrophonePreviewOwner(engine: .init(
            start: { order in
                let uid = order.entries.first?.uid
                recorder.startedUIDs.append(uid)
                recorder.running = true
                if let uid, gatedUIDs.contains(uid) {
                    await gate.wait()
                }
            },
            stop: {
                recorder.stopCount += 1
                recorder.running = false
            },
            isRunning: { recorder.running },
            level: { 0 }
        ))
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test work")
    }

    func testStopCancelsPendingStartAndCleansUpStaleBringUp() async {
        let gate = StartGate()
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder, gatedUIDs: ["a"], gate: gate)

        owner.start(order("a"))
        await waitUntil { recorder.startedUIDs.count == 1 }
        XCTAssertEqual(recorder.stopCount, 1)
        owner.stop()
        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(recorder.stopCount, 2)

        await gate.release()
        await waitUntil { recorder.stopCount == 3 }
        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(recorder.startedUIDs, ["a"], "the stale bring-up never delivers a tap")
    }

    func testRestartSupersedesInFlightStart() async {
        let gate = StartGate()
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder, gatedUIDs: ["a"], gate: gate)

        owner.start(order("a"))
        await waitUntil { recorder.startedUIDs.count == 1 }
        owner.start(order("b"))

        await gate.release()
        await waitUntil { recorder.startedUIDs.count == 2 }
        XCTAssertEqual(recorder.startedUIDs, ["a", "b"])
        XCTAssertEqual(recorder.stopCount, 3)
        XCTAssertTrue(owner.isActive)

        owner.stop()
        XCTAssertFalse(owner.isActive)
    }
}

@MainActor
final class InputLevelMonitorTests: XCTestCase {
    @MainActor private final class SlowMicrophone {
        var started = false
        var stops = 0
        var startGate: CheckedContinuation<Void, Never>?

        var boundary: Microphone {
            Microphone(
                requestAccess: { true },
                prepare: { _ in },
                start: { _ in
                    self.started = true
                    await withCheckedContinuation { self.startGate = $0 }
                    return PreviewAudioQueue()
                },
                stop: { self.stops += 1 }
            )
        }

        func finishStart() {
            startGate?.resume()
            startGate = nil
        }
    }

    func testStopDuringSlowPreviewStartNeverReportsListening() async {
        let microphone = SlowMicrophone()
        let monitor = InputLevelMonitor(microphone: microphone.boundary, isAuthorized: { true })
        let starting = Task { await monitor.start(MicrophoneOrder()) }
        for _ in 0..<1_000 where !microphone.started { await Task.yield() }
        XCTAssertTrue(microphone.started)
        XCTAssertFalse(monitor.isRunning)

        monitor.stop()
        microphone.finishStart()
        await starting.value
        XCTAssertFalse(monitor.isRunning)
        XCTAssertGreaterThanOrEqual(microphone.stops, 2)
    }
}
