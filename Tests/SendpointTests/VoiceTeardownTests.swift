import XCTest
@testable import Sendpoint

@MainActor
final class VoiceTeardownTests: XCTestCase {
    func testTeardownCancelsWarmupAndRejectsAllRestartPaths() async {
        let transcriber = TeardownTranscriber()
        var engineRequests = 0
        let service = VoiceNoteService(transcriber: transcriber, makeSpareEngine: {
            engineRequests += 1
            return nil
        })
        service.warmUp()
        await transcriber.waitUntilPreparing()
        service.teardown()
        let epoch = service.recordingEpoch
        service.teardown()
        service.discardRecording()
        service.warmUp()
        await service.waitForTeardown()

        XCTAssertEqual(service.recordingEpoch, epoch)
        XCTAssertEqual(engineRequests, 1)
        let snapshot = await transcriber.snapshot()
        XCTAssertEqual(snapshot.teardowns, 1)
        XCTAssertTrue(snapshot.cancelled)
        XCTAssertFalse(service.isRecording)
        service.applyTapLevel(1, epoch: epoch)
        XCTAssertEqual(service.levelMeter.current, 0)
        do {
            try await service.startRecording()
            XCTFail("A terminated service cannot record")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            try await service.downloadVoiceModel()
            XCTFail("A terminated service cannot download")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testDiscardRemainsRestartable() async {
        let transcriber = TeardownTranscriber()
        var engineRequests = 0
        let service = VoiceNoteService(transcriber: transcriber, makeSpareEngine: {
            engineRequests += 1
            return nil
        })
        service.discardRecording()
        service.warmUp()
        await transcriber.waitUntilPreparing()
        XCTAssertEqual(engineRequests, 1, "Discard must not terminate the service")
        service.teardown()
        await service.waitForTeardown()
    }

    func testLocalTranscriberTeardownIsTerminalWithoutLoadingModels() async {
        let transcriber = LocalStreamingPreview()
        await transcriber.teardown()
        await transcriber.teardown()
        await transcriber.abandon()
        do {
            try await transcriber.prepare()
            XCTFail("Teardown must prevent model loading")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let generation = await transcriber.begin(onPartial: { _ in })
        XCTAssertNil(generation)
    }
}

private actor TeardownTranscriber: VoiceTranscribing {
    private var preparing = false
    private var started: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var teardowns = 0
    private var cancelled = false

    func waitUntilPreparing() async {
        if preparing { return }
        await withCheckedContinuation { started = $0 }
    }

    func prepareIfNeeded() async {
        preparing = true
        started?.resume()
        started = nil
        await withCheckedContinuation { release = $0 }
        cancelled = Task.isCancelled
    }

    func teardown() {
        teardowns += 1
        release?.resume()
        release = nil
    }

    func snapshot() -> (teardowns: Int, cancelled: Bool) { (teardowns, cancelled) }
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {}
    func begin(onPartial: @escaping @Sendable (String) -> Void) async -> Int? { nil }
    func feed(_ frames: [PreviewAudioFrame], generation: Int) async {}
    func finish(leftover: [PreviewAudioFrame], generation: Int?) async throws -> String { "" }
    func abandon() async {}
}
