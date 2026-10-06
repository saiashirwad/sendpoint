import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class CaptureAudioIntegrationTests: XCTestCase {
    @MainActor private final class Gate<Value: Sendable> {
        private var value: Value?
        private var waiters: [CheckedContinuation<Value, Never>] = []
        func wait() async -> Value {
            if let value { return value }
            return await withCheckedContinuation { waiters.append($0) }
        }
        func open(_ value: Value) {
            self.value = value
            waiters.forEach { $0.resume(returning: value) }
            waiters.removeAll()
        }
    }

    @MainActor private final class Mic {
        var audio: VoiceAudioTake?
        var starts = 0
        var stops = 0
        var recording = false
        var boundary: Microphone {
            Microphone(requestAccess: { true }, prepare: { _ in }, start: { _, audio in
                self.starts += 1
                self.audio = audio
                audio?.append(VoiceAudioFrame(samples: [1], sampleRate: 16_000))
                self.recording = true
            }, stop: {
                self.stops += 1
                self.audio?.append(VoiceAudioFrame(samples: [3], sampleRate: 16_000))
                self.recording = false
            }, teardown: { self.audio = nil })
        }
    }

    private actor Engine {
        private(set) var samples: [Float] = []
        private(set) var finishes = 0
        let appended: AsyncAcknowledgement
        init(appended: AsyncAcknowledgement) { self.appended = appended }
        func append(_ frame: VoiceAudioFrame) async {
            samples += frame.samples
            await appended.signal()
        }
        func finish() -> String {
            finishes += 1
            return samples.map { [1: "first", 2: "middle", 3: "last"][$0] ?? "unexpected" }
                .joined(separator: " ")
        }
        var boundary: VoiceStreamingEngine {
            VoiceStreamingEngine(reset: {}, setPartial: { _ in },
                                 append: { await self.append($0) }, finish: { await self.finish() })
        }
    }

    @MainActor private final class Disk {
        var attempts: [StackDocument] = []
        let started = AsyncAcknowledgement()
        let first = Gate<Void>()
        let retry = Gate<Void>()
        func commit(_ document: StackDocument) async throws {
            attempts.append(document)
            let attempt = attempts.count
            started.signal()
            if attempt == 1 {
                await first.wait()
                throw CocoaError(.fileWriteOutOfSpace)
            }
            await retry.wait()
        }
    }

    func testAudioFinishJoinsSelectionFlushesLastFrameAndRetriesFrozenNote() async throws {
        let suite = "CaptureAudioIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "restoreFocusAfterSave")
        let permissions = PermissionController(services: PermissionServices(
            accessibilityStatus: { .granted }, requestAccessibility: { true },
            microphoneStatus: { .granted }, requestMicrophone: { true },
            voiceModelFilesExist: { true }, downloadVoiceModel: { _ in },
            openAccessibilitySettings: {}, openMicrophoneSettings: {}
        ))
        let mic = Mic()
        let appended = AsyncAcknowledgement()
        let engine = Engine(appended: appended)
        let transcriber = LocalStreamingTranscriber(load: { _ in await engine.boundary })
        var now = Date(timeIntervalSince1970: 1_000)
        let service = VoiceNoteService(transcriber: transcriber, microphone: mic.boundary,
                                       modelReady: { true }, now: { now })
        let disk = Disk()
        let store = try await StackStore(persistence: StorePersistence(
            load: { StackDocument() }, commit: { try await disk.commit($0) }
        ))
        let selection = Gate<CapturedSelection>()
        let selectionStarted = AsyncAcknowledgement()
        let timing = ControlledSleep()
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults), voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: permissions,
            selection: SelectionCapture(read: { _, _ in
                selectionStarted.signal()
                return await selection.wait()
            }, paste: { _, _ in false }), recorder: .live(service), frontApp: { nil },
            sleep: { try await timing.sleep($0) },
            surfaces: { _ in CaptureSurfaces(prepare: {}, show: { _ in }, focus: {}, close: {}, discard: {}) }
        )
        controller.configure(store: store)
        var transcripts: [String] = []
        let receive = service.onOutput
        service.onOutput = {
            if case let .transcript(_, text) = $0 { transcripts.append(text) }
            receive?($0)
        }
        addTeardownBlock { @MainActor in
            controller.teardown()
            selection.open(CapturedSelection(text: ""))
            disk.first.open(())
            disk.retry.open(())
            await store.waitForIdle()
            store.teardown()
            permissions.teardown()
            service.teardown()
            await service.waitForTeardown()
            defaults.removePersistentDomain(forName: suite)
        }

        controller.send(.voicePressed)
        await selectionStarted.wait()
        await appended.wait()
        await waitForObservation { controller.state.speech?.stage == .listening }
        let identity = try XCTUnwrap(controller.state.identity)
        XCTAssertTrue(mic.recording)
        controller.send(.toggleDestinations(identity))
        controller.chooseDestination(.two, context: identity)
        now.addTimeInterval(1)
        controller.send(.finishVoice)
        await timing.started.wait()
        store.select(.three)
        controller.send(.stackSelected(.three))
        XCTAssertEqual(controller.state.destination, .frozen(.two))
        XCTAssertEqual(mic.stops, 0, "Finishing must join the pending selection before stopping audio")
        XCTAssertTrue(mic.recording)
        mic.audio?.append(VoiceAudioFrame(samples: [2], sampleRate: 16_000))
        selection.open(CapturedSelection(text: "Selected quote"))

        await disk.started.wait()
        if case .terminated = mic.audio?.append(VoiceAudioFrame(samples: [4], sampleRate: 16_000)) {} else {
            XCTFail("The service must close the audio producer after the last microphone callback")
        }
        XCTAssertEqual(controller.state.speech?.preview, "first middle last")
        XCTAssertEqual(controller.captured?.text, "Selected quote")
        XCTAssertTrue(controller.isNoteFrozen)
        XCTAssertTrue(store.stacks.flatMap(\.notes).isEmpty)
        disk.first.open(())
        await store.waitForIdle()
        XCTAssertEqual(store.state, .halted)
        XCTAssertEqual(controller.note, "first middle last")
        XCTAssertTrue(store.stacks.flatMap(\.notes).isEmpty)
        controller.note = "Late edit"
        controller.send(.retry)
        controller.send(.retry)
        await disk.started.wait(for: 2)
        XCTAssertEqual(controller.note, "first middle last")
        XCTAssertTrue(store.stacks.flatMap(\.notes).isEmpty, "Retry must commit before publishing")
        disk.retry.open(())
        await store.waitForIdle()

        XCTAssertFalse(controller.isOpen)
        XCTAssertFalse(store.hasPendingMutations)
        XCTAssertNil(store.error, "A second enqueue would reject the already committed note")
        XCTAssertEqual(disk.attempts.count, 2)
        XCTAssertEqual(disk.attempts.first, disk.attempts.last)
        let note = try XCTUnwrap(disk.attempts.first?[.two].first)
        XCTAssertEqual(note.id, identity.noteID)
        XCTAssertEqual(note.createdAt, identity.createdAt)
        XCTAssertEqual(note.subject, .selection(quote: "Selected quote"))
        XCTAssertEqual(note.body, "first middle last")
        XCTAssertEqual(store.stack(id: .two).notes, [note])
        XCTAssertEqual(store.stacks.flatMap(\.notes), [note])
        XCTAssertEqual(store.currentStackID, .three)
        XCTAssertEqual(transcripts, [note.body])
        let samples = await engine.samples
        let finishes = await engine.finishes
        XCTAssertEqual(samples, [1, 2, 3])
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(mic.starts, 1)
        XCTAssertEqual(mic.stops, 1)
    }
}
