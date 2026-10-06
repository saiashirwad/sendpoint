import XCTest
@testable import Sendpoint

@MainActor
final class VoiceTranscriberLifecycleTests: XCTestCase {
    private actor Engine {
        enum Failure: Error { case append }
        private var finishWaiters: [CheckedContinuation<Void, Never>] = []
        var gateFinish = false
        var failAppend = false
        private var finishGate: CheckedContinuation<Void, Never>?
        private(set) var resets = 0
        private(set) var finishes = 0
        private(set) var callbacks = 0
        private(set) var samples: [Float] = []
        private(set) var resetDuringFinish = false

        func waitUntilFinishing() async {
            if finishGate != nil { return }
            await withCheckedContinuation { finishWaiters.append($0) }
        }
        func configure(gateFinish: Bool = false, failAppend: Bool = false) {
            self.gateFinish = gateFinish
            self.failAppend = failAppend
        }
        func releaseFinish() { finishGate?.resume(); finishGate = nil }
        func reset() {
            if finishGate != nil { resetDuringFinish = true }
            resets += 1
        }
        func append(_ frame: VoiceAudioFrame) throws {
            if failAppend { throw Failure.append }
            samples += frame.samples
        }
        func finish() async -> String {
            finishes += 1
            if gateFinish {
                gateFinish = false
                await withCheckedContinuation {
                    finishGate = $0
                    finishWaiters.forEach { $0.resume() }
                    finishWaiters.removeAll()
                }
            }
            return "words"
        }
        func callback() { callbacks += 1 }
        var boundary: VoiceStreamingEngine {
            VoiceStreamingEngine(reset: { await self.reset() }, setPartial: { _ in await self.callback() },
                                 append: { try await self.append($0) }, finish: { await self.finish() })
        }
    }

    private actor Loader {
        let engine: Engine
        private var gate: CheckedContinuation<Void, Never>?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var calls = 0
        init(engine: Engine) { self.engine = engine }
        func waitUntilLoading() async {
            if gate != nil { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func load() async -> VoiceStreamingEngine {
            calls += 1
            await withCheckedContinuation {
                gate = $0
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
            return await engine.boundary
        }
        func release() { gate?.resume(); gate = nil }
    }

    private func take(_ samples: [Float]) -> VoiceAudioTake {
        let take = VoiceAudioTake()
        for sample in samples { take.append(VoiceAudioFrame(samples: [sample], sampleRate: 16_000)) }
        take.close()
        take.close()
        return take
    }

    func testCloseDrainsAllFramesThenFlushesAndResetsExactlyOnce() async throws {
        let engine = Engine()
        let transcriber = LocalStreamingTranscriber(load: { _ in await engine.boundary })
        let audio = take((0..<1_000).map(Float.init))
        let text = try await transcriber.transcribe(audio, onPartial: { _ in })
        XCTAssertEqual(text, "words")
        let samples = await engine.samples
        let resets = await engine.resets
        let finishes = await engine.finishes
        let callbacks = await engine.callbacks
        XCTAssertEqual(samples, (0..<1_000).map(Float.init))
        XCTAssertEqual(resets, 2, "One opening reset and one cleanup reset")
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(callbacks, 2)
        if case .terminated = audio.append(VoiceAudioFrame(samples: [1_001], sampleRate: 16_000)) {} else {
            XCTFail("Closed producer accepted a frame")
        }
        await transcriber.teardown()
    }

    func testOverlappingLeaseIsRejectedUntilCancelledFinishActuallySettles() async throws {
        let engine = Engine()
        await engine.configure(gateFinish: true)
        let transcriber = LocalStreamingTranscriber(load: { _ in await engine.boundary })
        let first = Task { try await transcriber.transcribe(take([1]), onPartial: { _ in }) }
        await engine.waitUntilFinishing()
        first.cancel()
        do { _ = try await transcriber.transcribe(take([2]), onPartial: { _ in }); XCTFail("Overlapping lease opened") }
        catch VoiceTranscriptionError.busy {} catch { XCTFail("Unexpected error: \(error)") }
        let openingResets = await engine.resets
        XCTAssertEqual(openingResets, 1)
        await engine.releaseFinish()
        do { _ = try await first.value; XCTFail("Cancelled take returned a transcript") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let text = try await transcriber.transcribe(take([2]), onPartial: { _ in })
        let samples = await engine.samples
        let resets = await engine.resets
        let resetDuringFinish = await engine.resetDuringFinish
        XCTAssertEqual(text, "words")
        XCTAssertEqual(samples, [1, 2])
        XCTAssertEqual(resets, 4)
        XCTAssertFalse(resetDuringFinish)
        await transcriber.teardown()
    }

    func testFrameFailureIsNotSilentlyLostAndStillResetsTheLease() async {
        let engine = Engine()
        await engine.configure(failAppend: true)
        let transcriber = LocalStreamingTranscriber(load: { _ in await engine.boundary })
        do { _ = try await transcriber.transcribe(take([1]), onPartial: { _ in }); XCTFail("Expected append failure") }
        catch Engine.Failure.append {} catch { XCTFail("Unexpected error: \(error)") }
        let resets = await engine.resets
        let finishes = await engine.finishes
        XCTAssertEqual(resets, 2)
        XCTAssertEqual(finishes, 0)
        await transcriber.teardown()
    }

    func testCancelledTakeDoesNotCancelSharedPreparation() async throws {
        let engine = Engine()
        let loader = Loader(engine: engine)
        let transcriber = LocalStreamingTranscriber(load: { _ in await loader.load() })
        let preparation = Task { try await transcriber.prepare() }
        await loader.waitUntilLoading()
        let cancelled = Task { try await transcriber.transcribe(take([1]), onPartial: { _ in }) }
        cancelled.cancel()
        await loader.release()
        try await preparation.value
        do { _ = try await cancelled.value; XCTFail("Cancelled take returned a transcript") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        _ = try await transcriber.transcribe(take([2]), onPartial: { _ in })
        let loads = await loader.calls
        let samples = await engine.samples
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(samples, [2])
        await transcriber.teardown()
    }

    func testTeardownRejectsLatePreparationAndIsTerminal() async {
        let engine = Engine()
        let loader = Loader(engine: engine)
        let transcriber = LocalStreamingTranscriber(load: { _ in await loader.load() })
        let preparation = Task { try await transcriber.prepare() }
        await loader.waitUntilLoading()
        let teardown = Task { await transcriber.teardown() }
        for _ in 0..<100 { await Task.yield() }
        await loader.release()
        await teardown.value
        do { try await preparation.value; XCTFail("Late preparation must be rejected") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await transcriber.teardown()
        do { _ = try await transcriber.transcribe(take([1]), onPartial: { _ in }); XCTFail("Teardown is terminal") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let loads = await loader.calls
        XCTAssertEqual(loads, 1)
    }

    func testDefaultTranscriberTeardownPreventsAnyModelLoading() async {
        let transcriber = LocalStreamingTranscriber()
        await transcriber.teardown()
        await transcriber.teardown()
        do { try await transcriber.prepare(); XCTFail("Terminal transcriber must not load models") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do { _ = try await transcriber.transcribe(take([1]), onPartial: { _ in }); XCTFail("Terminal transcriber opened") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
