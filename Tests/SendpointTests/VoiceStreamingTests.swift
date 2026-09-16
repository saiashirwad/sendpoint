import AppKit
import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

/// Streaming behavior through the real controller wiring: partials update the
/// preview only while their capture is still recording, stale work is dropped,
/// and engine switches tear down cleanly. No microphone, no network.
@MainActor
final class VoiceStreamingTests: XCTestCase {
    private enum Fail: LocalizedError {
        case failed
        var errorDescription: String? { "mic busy" }
    }

    @MainActor private final class Surfaces {
        var events: [String] = []
        var boundary: CaptureSurfaces {
            CaptureSurfaces(
                prepare: { self.events.append("prepare") },
                show: { self.events.append("show \($0)") },
                focus: { self.events.append("focus") },
                stopEscapeHandling: { self.events.append("stopEscape") },
                close: { self.events.append("close") },
                discard: { self.events.append("discard") }
            )
        }
    }

    private actor Gate<Value: Sendable> {
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

    @MainActor private final class Recorder {
        var starts = 0
        var discards = 0
        var partialHandler: ((String) -> Void)?
        let started = Gate<Bool>()
        var boundary: VoiceRecorder {
            VoiceRecorder(
                start: {
                    self.starts += 1
                    _ = await self.started.wait()
                },
                stopAndTranscribe: { "final transcript" },
                discard: { self.discards += 1 },
                levelMeter: VoiceLevelMeter(),
                observePartials: { self.partialHandler = $0 }
            )
        }
    }

    private struct Fixture {
        let controller: CaptureController
        let store: StackStore
        let surfaces: Surfaces
        let recorder: Recorder
        let selectionGate: Gate<CapturedSelection>
    }

    private let selection = CapturedSelection(text: "A passage")

    private func makeFixture() async throws -> Fixture {
        let suite = "VoiceStreamingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "restoreFocusAfterSave")
        let permissions = PermissionState(services: PermissionServices(
            accessibilityStatus: { .granted }, requestAccessibility: { true },
            microphoneStatus: { .granted }, requestMicrophone: { true },
            voiceModelFilesExist: { true }, downloadVoiceModel: { _ in },
            openAccessibilitySettings: {}, openMicrophoneSettings: {}
        ))
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }))
        let surfaces = Surfaces()
        let recorder = Recorder()
        let gate = Gate<CapturedSelection>()
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults),
            voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: permissions,
            selection: SelectionCapture(
                read: { _, editorMayOpen in
                    editorMayOpen()
                    return await gate.wait()
                },
                paste: { _, _ in false }
            ),
            recorder: recorder.boundary,
            surfaces: { _ in surfaces.boundary }
        )
        controller.configure(store: store)
        return Fixture(controller: controller, store: store, surfaces: surfaces,
                       recorder: recorder, selectionGate: gate)
    }

    private func startRecording(_ f: Fixture) async {
        f.controller.send(.voicePressed)
        await waitUntil { f.recorder.starts == 1 }
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
        await waitUntil { f.controller.state.session?.phase == .recording }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the controller")
    }

    func testStreamingPartialUpdatesThePreviewWhileRecording() async throws {
        let f = try await makeFixture()
        await startRecording(f)

        f.recorder.partialHandler?("how is the")
        await waitUntil { f.controller.state.session?.liveTranscript == "how is the" }
        f.recorder.partialHandler?("how is the weather")
        await waitUntil { f.controller.state.session?.liveTranscript == "how is the weather" }

        // The preview never disturbs the workflow: still recording, no effects.
        XCTAssertEqual(f.controller.state.session?.phase, .recording)
        XCTAssertFalse(f.surfaces.events.contains("close"))
    }

    func testStalePartialForAnOldContextIsIgnored() async throws {
        let f = try await makeFixture()
        await startRecording(f)
        let oldContext = try XCTUnwrap(f.controller.state.session?.context)

        f.controller.send(.cancelVoice)
        await waitUntil { !f.controller.isOpen }

        f.controller.send(.voicePartial(oldContext, "late hypothesis"))
        await Task.yield()
        XCTAssertFalse(f.controller.isOpen, "a dead capture stays closed")
    }

    func testPartialOutsideRecordingPhasesIsIgnored() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        await waitUntil { f.surfaces.events == ["show editor"] }
        await f.selectionGate.open(selection)
        await waitUntil { f.controller.state.session?.target != nil }
        let context = try XCTUnwrap(f.controller.state.session?.context)

        f.controller.send(.voicePartial(context, "should not land"))
        await Task.yield()
        XCTAssertNil(f.controller.state.session?.liveTranscript)
        f.controller.teardown()
    }

    func testBlankPartialClearsThePreviewAndFailureClearsItToo() async throws {
        let f = try await makeFixture()
        await startRecording(f)
        let context = try XCTUnwrap(f.controller.state.session?.context)

        f.controller.send(.voicePartial(context, "something"))
        await waitUntil { f.controller.state.session?.liveTranscript == "something" }
        f.controller.send(.voicePartial(context, "   "))
        await waitUntil { f.controller.state.session?.liveTranscript == nil }

        f.controller.send(.voicePartial(context, "again"))
        await waitUntil { f.controller.state.session?.liveTranscript == "again" }
        f.controller.send(.failed(context, "boom"))
        XCTAssertNil(f.controller.state.session?.liveTranscript)
    }

    func testVoiceModelFilesAreUnifiedStreamingNotLegacyTDT() {
        XCTAssertEqual(
            LocalVoiceModelFiles.cacheDirectory.lastPathComponent,
            "parakeet-unified-en-0.6b"
        )
        XCTAssertTrue(
            LocalVoiceModelFiles.requiredFileNames.contains { $0.contains("70_2_2") },
            "setup must look for the 320ms Unified encoder, not TDT or EOU"
        )
        XCTAssertFalse(LocalVoiceModelFiles.requiredFileNames.contains { $0.contains("tdt") })
        XCTAssertFalse(LocalVoiceModelFiles.requiredFileNames.contains { $0.contains("eou") })
    }

    func testPreviewWrapsWithoutReflowingCompletedLines() {
        let font = NSFont.ui(LiveTranscriptPreview.fontSize)
        let width = ("aaaaa aaaaa" as NSString).size(withAttributes: [.font: font]).width
        let first = LiveTranscriptPreview.lines(for: "aaaaa aaaaa", width: width, font: font)
        XCTAssertEqual(first, ["aaaaa aaaaa"])

        let wrapped = LiveTranscriptPreview.lines(for: "aaaaa aaaaa bbbbb", width: width, font: font)
        XCTAssertEqual(wrapped.first, "aaaaa aaaaa", "appending a word must not reflow the previous line")
        XCTAssertEqual(wrapped.last, "bbbbb")

        let many = LiveTranscriptPreview.lines(
            for: Array(repeating: "aaaaa", count: 10).joined(separator: " "),
            width: width,
            font: font
        )
        XCTAssertGreaterThan(many.count, 4)
        XCTAssertEqual(LiveTranscriptPreview.visible(many).count, 4)
        XCTAssertEqual(LiveTranscriptPreview.visible(many), Array(many.suffix(4)))
        XCTAssertTrue(LiveTranscriptPreview.lines(for: "", width: width, font: font).isEmpty)
    }
}
