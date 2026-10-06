import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class VoiceNoteServiceTests: XCTestCase {
    @MainActor private final class Mic {
        var starts = 0
        var stops = 0
        var teardowns = 0
        var prepares = 0
        var allowed = true
        var suspendStart = false
        var suspendAccess = false
        var suspendPrepare = false
        var startGate: CheckedContinuation<Void, Never>?
        var accessGate: CheckedContinuation<Bool, Never>?
        var prepareGate: CheckedContinuation<Void, Never>?
        var finishedPrepares = 0
        var audio: VoiceAudioTake?
        var lastFrame: Float?
        let started = AsyncAcknowledgement()
        let stopped = AsyncAcknowledgement()
        let prepared = AsyncAcknowledgement()
        let accessRequested = AsyncAcknowledgement()

        func releaseStart() { startGate?.resume(); startGate = nil }
        func releaseAccess() { accessGate?.resume(returning: allowed); accessGate = nil }
        func releasePrepare() { prepareGate?.resume(); prepareGate = nil }

        var boundary: Microphone {
            Microphone(
                requestAccess: {
                    if self.suspendAccess {
                        return await withCheckedContinuation {
                            self.accessGate = $0
                            self.accessRequested.signal()
                        }
                    }
                    return self.allowed
                },
                prepare: { _ in
                    self.prepares += 1
                    if self.suspendPrepare {
                        await withCheckedContinuation { self.prepareGate = $0; self.prepared.signal() }
                    } else { self.prepared.signal() }
                    self.finishedPrepares += 1
                },
                start: { _, audio in
                    self.starts += 1
                    self.audio = audio
                    if self.suspendStart {
                        await withCheckedContinuation { self.startGate = $0; self.started.signal() }
                    } else { self.started.signal() }
                },
                stop: {
                    self.stops += 1
                    if let last = self.lastFrame {
                        self.audio?.append(VoiceAudioFrame(samples: [last], sampleRate: 16_000))
                    }
                    self.stopped.signal()
                },
                teardown: { self.teardowns += 1 }
            )
        }
    }

    private struct Fixture {
        let service: VoiceNoteService
        let transcriber: FakeTranscriber
        let mic: Mic
        let outputs: Outputs
    }
    @MainActor private final class Outputs {
        var all: [VoiceOutput] = []
        let delivered = AsyncAcknowledgement()
    }

    private func makeFixture(modelReady: Bool = true, clipDuration: TimeInterval = 1) -> Fixture {
        let transcriber = FakeTranscriber()
        let mic = Mic()
        let outputs = Outputs()
        var clock = Date(timeIntervalSince1970: 1_000)
        let service = VoiceNoteService(
            transcriber: transcriber, microphone: mic.boundary, modelReady: { modelReady },
            now: { clock.addTimeInterval(clipDuration); return clock }
        )
        service.onOutput = { outputs.all.append($0); outputs.delivered.signal() }
        addTeardownBlock { @MainActor in
            mic.releaseStart()
            mic.releaseAccess()
            mic.releasePrepare()
            await transcriber.releaseFinish(with: "")
            service.teardown()
            await service.waitForTeardown()
        }
        return Fixture(service: service, transcriber: transcriber, mic: mic, outputs: outputs)
    }

    func testDiscardWaitsForActualSettlementBeforeRestartAndDropsLateTranscript() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()
        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        f.service.discard()
        let next = UUID()
        f.service.start(next)
        XCTAssertEqual(f.service.machine.phase, .settling(next: next))
        XCTAssertEqual(f.mic.starts, 1)

        await f.transcriber.emitPartial("too late", take: take)
        await f.transcriber.releaseFinish(with: "too late")
        await f.outputs.delivered.wait(for: 2)
        XCTAssertEqual(f.outputs.all, [.started(take), .started(next)])
        XCTAssertEqual(f.mic.starts, 2)
    }

    func testClosingATypedNoteNeverTouchesTheModel() async {
        let f = makeFixture()
        f.service.discard()
        f.service.discard()
        let operations = await f.transcriber.operations
        XCTAssertEqual(operations, 0)
        XCTAssertEqual(f.mic.stops, 0)
    }

    func testRecordingDrainsEveryFrameIncludingTheLastStopCallback() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()
        for index in 0..<100 {
            f.mic.audio?.append(VoiceAudioFrame(samples: [Float(index)], sampleRate: 16_000))
        }
        f.mic.lastFrame = 100
        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        let samples = await f.transcriber.samples
        XCTAssertEqual(samples, (0...100).map(Float.init))
        if case .terminated = f.mic.audio?.append(VoiceAudioFrame(samples: [101], sampleRate: 16_000)) {} else {
            XCTFail("Stop must close the producer")
        }
        await f.transcriber.releaseFinish(with: "  spoken words ")
        await f.outputs.delivered.wait(for: 2)
        XCTAssertEqual(f.outputs.all, [.started(take), .transcript(take, "spoken words")])
        XCTAssertEqual(f.service.machine.phase, .idle)
        XCTAssertEqual(f.mic.stops, 1)
    }

    func testDiscardDuringSlowMicrophoneStartRejectsLateStart() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        f.service.start(UUID())
        await f.mic.started.wait()
        f.service.discard()
        XCTAssertEqual(f.service.machine.phase, .idle)
        f.mic.suspendStart = false
        f.mic.releaseStart()
        await f.mic.stopped.wait()
        XCTAssertTrue(f.outputs.all.isEmpty)
        f.service.start(UUID())
        await f.outputs.delivered.wait()
        XCTAssertEqual(f.mic.starts, 2)
    }

    func testLatePermissionResponseCannotStartAReplacedTake() async {
        let f = makeFixture()
        f.mic.suspendAccess = true
        f.service.start(UUID())
        await f.mic.accessRequested.wait()
        let next = UUID()
        f.service.start(next)
        f.mic.suspendAccess = false
        f.mic.releaseAccess()
        await f.outputs.delivered.wait()
        XCTAssertEqual(f.mic.starts, 1)
        XCTAssertEqual(f.outputs.all, [.started(next)])
    }

    func testChangedMicrophoneOrderRestartsPendingStartBeforeReportingRecording() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        let take = UUID()
        f.service.start(take)
        await f.mic.started.wait()
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: "new", name: "New", transport: .builtIn)], systemDefault: nil)
        f.service.microphones = order
        f.mic.suspendStart = false
        f.mic.releaseStart()
        await f.outputs.delivered.wait()
        XCTAssertEqual(f.mic.starts, 2)
        XCTAssertEqual(f.mic.stops, 1)
    }

    func testMissingModelOrDeniedMicrophoneFailsWithoutRecording() async {
        let missing = makeFixture(modelReady: false)
        let take = UUID()
        missing.service.start(take)
        XCTAssertEqual(missing.outputs.all, [.failed(take, VoiceMachine.modelMissing)])
        XCTAssertEqual(missing.mic.starts, 0)
        let denied = makeFixture()
        denied.mic.allowed = false
        denied.service.start(take)
        await denied.outputs.delivered.wait()
        XCTAssertEqual(denied.mic.starts, 0)
        guard case .failed(take, _)? = denied.outputs.all.first else { return XCTFail("Expected failure") }
    }

    func testShortClipYieldsEmptyTranscriptWithoutFinalFlush() async {
        let f = makeFixture(clipDuration: 0.1)
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()
        f.service.stop(take)
        await f.outputs.delivered.wait(for: 2)
        XCTAssertEqual(f.outputs.all, [.started(take), .transcript(take, "")])
        let finishes = await f.transcriber.finishes
        XCTAssertEqual(finishes, 0)
    }

    func testWarmUpSkipsTheModelUntilItsFilesExist() async {
        let missing = makeFixture(modelReady: false)
        missing.service.warmUp()
        await missing.mic.prepared.wait()
        let skipped = await missing.transcriber.prepares
        XCTAssertEqual(skipped, 0)
        let ready = makeFixture()
        ready.service.warmUp()
        ready.service.warmUp()
        await ready.transcriber.prepared.wait()
    }

    func testTeardownIsTerminalAndStopsEverything() async {
        let f = makeFixture()
        f.service.start(UUID())
        await f.outputs.delivered.wait()
        f.service.teardown()
        f.service.teardown()
        await f.service.waitForTeardown()
        let teardowns = await f.transcriber.teardowns
        XCTAssertEqual(teardowns, 1)
        XCTAssertEqual(f.service.machine.phase, .tornDown)
        XCTAssertEqual(f.mic.teardowns, 1)
        f.service.start(UUID())
        f.service.warmUp()
        XCTAssertEqual(f.mic.starts, 1)
        XCTAssertEqual(f.mic.prepares, 0)
    }

    func testRecordingFailureStopsTheProducerAndSettlesBeforeRestart() async throws {
        let f = makeFixture()
        let id = UUID()
        f.service.start(id)
        await f.outputs.delivered.wait()
        let audio = try XCTUnwrap(f.mic.audio)
        await f.transcriber.failOnFrame()
        audio.append(VoiceAudioFrame(samples: [1], sampleRate: 16_000))
        await f.outputs.delivered.wait(for: 2)
        guard case .failed(id, _) = f.outputs.all[1] else { return XCTFail("Expected current take failure") }
        let next = UUID()
        f.service.start(next)
        await f.outputs.delivered.wait(for: 3)
        XCTAssertEqual(f.mic.stops, 1)
        XCTAssertEqual(f.outputs.all.last, .started(next))
        if case .terminated = audio.append(VoiceAudioFrame(samples: [2], sampleRate: 16_000)) {} else {
            XCTFail("Failed take left its producer open")
        }
    }

    func testWarmUpRemainsOwnedAcrossStartAndTeardown() async {
        let f = makeFixture()
        f.mic.suspendPrepare = true
        f.service.warmUp()
        await f.mic.prepared.wait()
        f.service.start(UUID())
        f.service.warmUp()
        XCTAssertEqual(f.mic.prepares, 1)
        f.service.teardown()
        var completed = false
        let shutdown = Task { await f.service.waitForTeardown(); completed = true }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(completed)
        f.mic.releasePrepare()
        await shutdown.value
        XCTAssertEqual(f.mic.finishedPrepares, 1)
        XCTAssertEqual(f.mic.starts, 0)
        XCTAssertEqual(f.mic.teardowns, 1)
    }
}

private actor FakeTranscriber: VoiceTranscribing {
    enum Failure: Error { case frame }
    let prepared: AsyncAcknowledgement
    @MainActor init() { prepared = AsyncAcknowledgement() }
    private(set) var teardowns = 0
    private(set) var prepares = 0
    private(set) var operations = 0
    private(set) var finishes = 0
    private(set) var samples: [Float] = []
    private var partials: [UUID: @Sendable (String) -> Void] = [:]
    private var finishing: CheckedContinuation<String, Never>?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldFailOnFrame = false

    func waitUntilFinishing() async {
        if finishing != nil { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
    func releaseFinish(with text: String) { finishing?.resume(returning: text); finishing = nil }
    func emitPartial(_ text: String, take: UUID) { partials[take]?(text) }
    func failOnFrame() { shouldFailOnFrame = true }
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {}
    func prepareIfNeeded() async { prepares += 1; await prepared.signal() }
    func transcribe(_ take: VoiceAudioTake, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        operations += 1
        partials[take.id] = onPartial
        for await frame in take.frames {
            try Task.checkCancellation()
            if shouldFailOnFrame { shouldFailOnFrame = false; throw Failure.frame }
            samples += frame.samples
        }
        try Task.checkCancellation()
        finishes += 1
        return await withCheckedContinuation {
            finishing = $0
            finishWaiters.forEach { $0.resume() }
            finishWaiters.removeAll()
        }
    }
    func teardown() async { teardowns += 1; releaseFinish(with: "") }
}
