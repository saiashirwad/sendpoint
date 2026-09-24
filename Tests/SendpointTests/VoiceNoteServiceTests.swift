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
        var startGate: CheckedContinuation<Void, Never>?

        func releaseStart() {
            startGate?.resume()
            startGate = nil
        }

        var boundary: Microphone {
            Microphone(
                requestAccess: { self.allowed },
                prepare: { _ in self.prepares += 1 },
                start: { _ in
                    self.starts += 1
                    if self.suspendStart {
                        await withCheckedContinuation { self.startGate = $0 }
                    }
                    return VoiceAudioQueue()
                },
                stop: { self.stops += 1 },
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
    }

    private func makeFixture(modelReady: Bool = true) -> Fixture {
        let transcriber = FakeTranscriber()
        let mic = Mic()
        let outputs = Outputs()
        var clock = Date(timeIntervalSince1970: 1_000)
        let service = VoiceNoteService(
            transcriber: transcriber, microphone: mic.boundary,
            modelReady: { modelReady },
            now: {
                clock.addTimeInterval(1)
                return clock
            }
        )
        service.onOutput = { outputs.all.append($0) }
        return Fixture(service: service, transcriber: transcriber, mic: mic, outputs: outputs)
    }

    func testEscapeDuringTranscriptionAbandonsTheModelAndDropsTheLateTranscript() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await waitUntil { f.outputs.all == [.started(take)] }

        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        XCTAssertEqual(f.service.machine.phase, .transcribing(take))

        f.service.discard()
        await waitUntil { f.service.machine.phase == .idle }
        let abandons = await f.transcriber.abandons
        XCTAssertEqual(abandons, 1)

        await f.transcriber.releaseFinish(with: "too late")
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(f.outputs.all, [.started(take)], "the cancelled transcript never reaches the capture")
    }

    func testClosingATypedNoteNeverTouchesTheModel() async {
        let f = makeFixture()
        f.service.discard()
        f.service.discard()
        for _ in 0..<200 { await Task.yield() }
        let abandons = await f.transcriber.abandons
        XCTAssertEqual(abandons, 0)
        XCTAssertEqual(f.mic.stops, 0)
    }

    func testARecordingDeliversItsTranscript() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await waitUntil { f.outputs.all == [.started(take)] }
        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        await f.transcriber.releaseFinish(with: "  spoken words ")
        await waitUntil { f.outputs.all.count == 2 }

        XCTAssertEqual(f.outputs.all, [.started(take), .transcript(take, "spoken words")])
        XCTAssertEqual(f.service.machine.phase, .idle)
        XCTAssertEqual(f.mic.stops, 1)
    }

    func testDiscardDuringSlowMicrophoneStartKeepsTheAppResponsiveAndRejectsTheLateStart() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        let discarded = UUID()
        f.service.start(discarded)
        await waitUntil { f.mic.startGate != nil }

        f.service.discard()
        XCTAssertEqual(f.service.machine.phase, .idle)
        XCTAssertTrue(f.outputs.all.isEmpty)

        f.mic.suspendStart = false
        f.mic.releaseStart()
        await waitUntil { f.mic.stops == 1 }
        XCTAssertTrue(f.outputs.all.isEmpty, "a cancelled microphone must not reopen capture")

        let next = UUID()
        f.service.start(next)
        await waitUntil { f.outputs.all == [.started(next)] }
        XCTAssertEqual(f.mic.starts, 2)
    }

    func testChangedMicrophoneOrderRestartsPendingStartBeforeReportingRecording() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        let take = UUID()
        f.service.start(take)
        await waitUntil { f.mic.startGate != nil }

        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: "new", name: "New", transport: .builtIn)],
                     systemDefault: nil)
        f.service.microphones = order
        f.mic.suspendStart = false
        f.mic.releaseStart()

        await waitUntil { f.outputs.all == [.started(take)] }
        XCTAssertEqual(f.mic.starts, 2)
        XCTAssertEqual(f.mic.stops, 1)
    }

    func testAMissingModelOrDeniedMicrophoneFailsWithoutRecording() async {
        let missing = makeFixture(modelReady: false)
        let take = UUID()
        missing.service.start(take)
        XCTAssertEqual(missing.outputs.all, [.failed(take, VoiceMachine.modelMissing)])
        XCTAssertEqual(missing.mic.starts, 0)

        let denied = makeFixture()
        denied.mic.allowed = false
        denied.service.start(take)
        await waitUntil { !denied.outputs.all.isEmpty }
        XCTAssertEqual(denied.mic.starts, 0)
        guard case .failed(take, _)? = denied.outputs.all.first else {
            return XCTFail("expected a failure, got \(denied.outputs.all)")
        }
    }

    func testWarmUpSkipsTheModelUntilItsFilesExist() async {
        let missing = makeFixture(modelReady: false)
        missing.service.warmUp()
        for _ in 0..<200 { await Task.yield() }
        let skipped = await missing.transcriber.prepares
        XCTAssertEqual(skipped, 0, "warming up must never start a download")
        XCTAssertEqual(missing.mic.prepares, 1)

        let ready = makeFixture()
        ready.service.warmUp()
        ready.service.warmUp()
        await waitUntil { await ready.transcriber.prepares == 1 }
    }

    func testTeardownIsTerminalAndStopsEverything() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await waitUntil { f.outputs.all == [.started(take)] }

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

    func testLocalTranscriberTeardownIsTerminalWithoutLoadingModels() async {
        let transcriber = LocalStreamingTranscriber()
        await transcriber.teardown()
        await transcriber.teardown()
        await transcriber.abandon()
        do {
            try await transcriber.prepare()
            XCTFail("Teardown must prevent model loading")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let opened = await transcriber.begin(UUID(), onPartial: { _ in })
        XCTAssertFalse(opened)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<5000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out")
    }
}

private actor FakeTranscriber: VoiceTranscribing {
    private(set) var abandons = 0
    private(set) var teardowns = 0
    private(set) var prepares = 0
    private var finishing: CheckedContinuation<String, Never>?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilFinishing() async {
        if finishing != nil { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }

    func releaseFinish(with text: String) {
        finishing?.resume(returning: text)
        finishing = nil
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {}
    func prepareIfNeeded() async { prepares += 1 }
    func begin(_ take: UUID, onPartial: @escaping @Sendable (String) -> Void) async -> Bool { true }
    func feed(_ frames: [VoiceAudioFrame], take: UUID) async {}

    func finish(_ take: UUID, leftover: [VoiceAudioFrame]) async throws -> String {
        await withCheckedContinuation { continuation in
            finishing = continuation
            finishWaiters.forEach { $0.resume() }
            finishWaiters.removeAll()
        }
    }

    func abandon() async { abandons += 1 }
    func teardown() async {
        teardowns += 1
        releaseFinish(with: "")
    }
}
