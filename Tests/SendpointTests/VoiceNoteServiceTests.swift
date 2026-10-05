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
        var startGate: CheckedContinuation<Void, Never>?
        let started = AsyncAcknowledgement()
        let stopped = AsyncAcknowledgement()
        let prepared = AsyncAcknowledgement()

        func releaseStart() {
            startGate?.resume()
            startGate = nil
        }

        var boundary: Microphone {
            Microphone(
                requestAccess: { self.allowed },
                prepare: { _ in
                    self.prepares += 1
                    self.prepared.signal()
                },
                start: { _ in
                    self.starts += 1
                    if self.suspendStart {
                        await withCheckedContinuation {
                            self.startGate = $0
                            self.started.signal()
                        }
                    } else {
                        self.started.signal()
                    }
                    return VoiceAudioQueue()
                },
                stop: {
                    self.stops += 1
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
        let timing: ControlledSleep
    }

    @MainActor private final class Outputs {
        var all: [VoiceOutput] = []
        let delivered = AsyncAcknowledgement()
    }

    private func makeFixture(modelReady: Bool = true, openResults: [Bool] = []) -> Fixture {
        let transcriber = FakeTranscriber(openResults: openResults)
        let mic = Mic()
        let outputs = Outputs()
        let timing = ControlledSleep()
        var clock = Date(timeIntervalSince1970: 1_000)
        let service = VoiceNoteService(
            transcriber: transcriber, microphone: mic.boundary,
            modelReady: { modelReady },
            now: {
                clock.addTimeInterval(1)
                return clock
            },
            sleep: { try await timing.sleep($0) }
        )
        service.onOutput = {
            outputs.all.append($0)
            outputs.delivered.signal()
        }
        addTeardownBlock { @MainActor in
            mic.releaseStart()
            service.teardown()
            await service.waitForTeardown()
        }
        return Fixture(service: service, transcriber: transcriber, mic: mic, outputs: outputs, timing: timing)
    }

    func testEscapeDuringTranscriptionAbandonsTheModelAndDropsTheLateTranscript() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()

        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        XCTAssertEqual(f.service.machine.phase, .transcribing(take))

        f.service.discard()
        let next = UUID()
        f.service.start(next)
        await f.outputs.delivered.wait(for: 2)
        let abandons = await f.transcriber.abandons
        XCTAssertEqual(abandons, 1)

        await f.transcriber.releaseFinish(with: "too late")
        await f.transcriber.finishReturned.wait()
        f.service.teardown()
        await f.service.waitForTeardown()
        XCTAssertEqual(f.outputs.all, [.started(take), .started(next)], "the cancelled transcript never reaches the capture")
    }

    func testClosingATypedNoteNeverTouchesTheModel() async {
        let f = makeFixture()
        f.service.discard()
        f.service.discard()
        let abandons = await f.transcriber.abandons
        XCTAssertEqual(abandons, 0)
        XCTAssertEqual(f.mic.stops, 0)
    }

    func testARecordingDeliversItsTranscript() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()
        f.service.stop(take)
        await f.transcriber.waitUntilFinishing()
        await f.transcriber.releaseFinish(with: "  spoken words ")
        await f.outputs.delivered.wait(for: 2)

        XCTAssertEqual(f.outputs.all, [.started(take), .transcript(take, "spoken words")])
        XCTAssertEqual(f.service.machine.phase, .idle)
        XCTAssertEqual(f.mic.stops, 1)
    }

    func testDiscardDuringSlowMicrophoneStartKeepsTheAppResponsiveAndRejectsTheLateStart() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        let discarded = UUID()
        f.service.start(discarded)
        await f.mic.started.wait()

        f.service.discard()
        XCTAssertEqual(f.service.machine.phase, .idle)
        XCTAssertTrue(f.outputs.all.isEmpty)

        f.mic.suspendStart = false
        f.mic.releaseStart()
        await f.mic.stopped.wait()
        XCTAssertTrue(f.outputs.all.isEmpty, "a cancelled microphone must not reopen capture")

        let next = UUID()
        f.service.start(next)
        await f.outputs.delivered.wait()
        XCTAssertEqual(f.mic.starts, 2)
    }

    func testChangedMicrophoneOrderRestartsPendingStartBeforeReportingRecording() async {
        let f = makeFixture()
        f.mic.suspendStart = true
        let take = UUID()
        f.service.start(take)
        await f.mic.started.wait()

        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: "new", name: "New", transport: .builtIn)],
                     systemDefault: nil)
        f.service.microphones = order
        f.mic.suspendStart = false
        f.mic.releaseStart()

        await f.outputs.delivered.wait()
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
        await denied.outputs.delivered.wait()
        XCTAssertEqual(denied.mic.starts, 0)
        guard case .failed(take, _)? = denied.outputs.all.first else {
            return XCTFail("expected a failure, got \(denied.outputs.all)")
        }
    }

    func testWarmUpSkipsTheModelUntilItsFilesExist() async {
        let missing = makeFixture(modelReady: false)
        missing.service.warmUp()
        await missing.mic.prepared.wait()
        let skipped = await missing.transcriber.prepares
        XCTAssertEqual(skipped, 0, "warming up must never start a download")
        XCTAssertEqual(missing.mic.prepares, 1)

        let ready = makeFixture()
        ready.service.warmUp()
        ready.service.warmUp()
        await ready.transcriber.prepared.wait()
    }

    func testTeardownIsTerminalAndStopsEverything() async {
        let f = makeFixture()
        let take = UUID()
        f.service.start(take)
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

    func testStreamRetriesOnlyAfterTheInjectedDelayAndCancelsIdlePolling() async {
        let f = makeFixture(openResults: [false, true])
        let take = UUID()
        f.service.start(take)
        await f.outputs.delivered.wait()
        await f.timing.started.wait()
        XCTAssertEqual(f.timing.durations, [.milliseconds(50)])
        let firstAttempts = await f.transcriber.begins
        XCTAssertEqual(firstAttempts, 1)
        f.timing.advance(.milliseconds(50))
        await f.timing.started.wait(for: 2)
        XCTAssertEqual(f.timing.durations, [.milliseconds(50), .milliseconds(5)])
        let attempts = await f.transcriber.begins
        XCTAssertEqual(attempts, 2)
        f.service.teardown()
        await f.service.waitForTeardown()
        await f.timing.completed.wait(for: 2)
        XCTAssertEqual(f.outputs.all, [.started(take)])
    }

    func testTeardownCancelsStreamRetryWithoutAnotherOpenAttempt() async {
        let f = makeFixture(openResults: [false, true])
        f.service.start(UUID())
        await f.timing.started.wait()
        f.service.teardown()
        await f.service.waitForTeardown()
        await f.timing.completed.wait()
        f.timing.advance(.milliseconds(50))
        let attempts = await f.transcriber.begins
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(f.service.machine.phase, .tornDown)
    }
}

private actor FakeTranscriber: VoiceTranscribing {
    let prepared: AsyncAcknowledgement
    let finishReturned: AsyncAcknowledgement
    private var openResults: [Bool]
    private(set) var begins = 0

    @MainActor init(openResults: [Bool] = []) {
        prepared = AsyncAcknowledgement()
        finishReturned = AsyncAcknowledgement()
        self.openResults = openResults
    }
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
    func prepareIfNeeded() async {
        prepares += 1
        await prepared.signal()
    }
    func begin(_ take: UUID, onPartial: @escaping @Sendable (String) -> Void) async -> Bool {
        begins += 1
        return openResults.isEmpty ? true : openResults.removeFirst()
    }
    func feed(_ frames: [VoiceAudioFrame], take: UUID) async {}

    func finish(_ take: UUID, leftover: [VoiceAudioFrame]) async throws -> String {
        let text = await withCheckedContinuation { continuation in
            finishing = continuation
            finishWaiters.forEach { $0.resume() }
            finishWaiters.removeAll()
        }
        await finishReturned.signal()
        return text
    }

    func abandon() async { abandons += 1 }
    func teardown() async {
        teardowns += 1
        releaseFinish(with: "")
    }
}
