import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

/// The capture controller against fakes: no microphone, no Accessibility,
/// no windows. Tests observe what it asked its boundaries to do.
@MainActor
final class CaptureControllerTests: XCTestCase {
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
        var startFails = false
        var transcript: Result<String, Error> = .success("hello there")
        let started = Gate<Bool>()
        var boundary: VoiceRecorder {
            VoiceRecorder(
                start: {
                    self.starts += 1
                    if self.startFails { throw Fail.failed }
                    _ = await self.started.wait()
                },
                stopAndTranscribe: { try self.transcript.get() },
                discard: { self.discards += 1 },
                levelMeter: VoiceLevelMeter()
            )
        }
    }

    private struct Fixture {
        let controller: CaptureController
        let store: StackStore
        let surfaces: Surfaces
        let recorder: Recorder
        let selectionGate: Gate<CapturedSelection>
        var accessibilityRequests = 0
    }

    private let selection = CapturedSelection(text: "A passage")

    private func makeFixture(accessibility: AccessibilityPermissionState = .granted) async throws -> Fixture {
        let suite = "CaptureControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "restoreFocusAfterSave")
        let permissions = PermissionState(services: PermissionServices(
            accessibilityStatus: { accessibility }, requestAccessibility: { true },
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

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the controller")
    }

    func testTypedNoteOpensTheEditorEarlyThenSavesAndCloses() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        XCTAssertEqual(f.surfaces.events, [], "nothing shows until the reader lets go of the front app")
        await waitUntil { f.surfaces.events == ["show editor"] }
        XCTAssertEqual(f.controller.captured, nil)

        await f.selectionGate.open(selection)
        await waitUntil { f.controller.captured == self.selection }
        f.controller.note = "A thought"
        f.controller.send(.save)
        await f.store.waitForIdle()
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentNotes.map(\.body), ["A thought"])
        XCTAssertEqual(f.store.currentNotes.first?.subject, .selection(quote: "A passage"))
        XCTAssertEqual(f.surfaces.events.last, "close")
    }

    func testVoiceHoldRecordsTranscribesAndSavesTheTranscript() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.surfaces.events, ["show voice"])
        await waitUntil { f.recorder.starts == 1 }
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
        await waitUntil { f.controller.state.session?.phase == .recording }

        f.controller.send(.voiceReleased)
        XCTAssertEqual(f.surfaces.events.last, "stopEscape")
        await f.store.waitForIdle()
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentNotes.map(\.body), ["hello there"])
        XCTAssertEqual(f.recorder.discards, 1, "closing releases the microphone once")
        XCTAssertEqual(f.controller.state.voice, VoiceGesture())
    }

    func testReleaseBeforeTheMicrophoneOpensEndsQuietly() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        await waitUntil { f.recorder.starts == 1 }
        f.controller.send(.voiceReleased)

        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events, ["show voice", "close"])
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
        await Task.yield()
        XCTAssertFalse(f.controller.isOpen, "late results find no capture")
        XCTAssertTrue(f.store.currentNotes.isEmpty)
    }

    func testEscapeDuringRecordingDiscardsTheClip() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        await waitUntil { f.recorder.starts == 1 }
        await f.recorder.started.open(true)
        await waitUntil { f.controller.state.session?.phase != .selectingVoice(recording: false, finishRequested: false) }

        f.controller.send(.voiceEscape)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.recorder.discards, 1)
        XCTAssertEqual(f.surfaces.events.last, "close")
        f.controller.send(.voiceReleased)
        XCTAssertTrue(f.store.currentNotes.isEmpty)
        await f.selectionGate.open(selection)
    }

    func testRecordingAndTranscriptionFailuresShowAMessageAndKeepTheStore() async throws {
        let failing = try await makeFixture()
        failing.recorder.startFails = true
        failing.controller.send(.voicePressed)
        await waitUntil { failing.controller.state.session?.phase == .failed("mic busy") }
        XCTAssertEqual(failing.recorder.discards, 1)
        failing.controller.send(.voiceEscape)
        XCTAssertFalse(failing.controller.isOpen)
        await failing.selectionGate.open(selection)

        let silent = try await makeFixture()
        silent.recorder.transcript = .success("   ")
        silent.controller.send(.voicePressed)
        await waitUntil { silent.recorder.starts == 1 }
        await silent.recorder.started.open(true)
        await silent.selectionGate.open(selection)
        await waitUntil { silent.controller.state.session?.phase == .recording }
        silent.controller.send(.voiceReleased)
        await waitUntil { silent.controller.state.session?.phase == .failed("No speech was found.") }
        XCTAssertTrue(silent.store.currentNotes.isEmpty)
    }

    func testMissingAccessibilityAsksOncePerPress() async throws {
        var f = try await makeFixture(accessibility: .notGranted)
        f.controller.onAccessibilityRequired = { f.accessibilityRequests += 1 }
        f.controller.send(.voicePressed)
        f.controller.send(.voicePressed)
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.accessibilityRequests, 1)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events, [])

        f.controller.send(.voiceReleased)
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.accessibilityRequests, 2)
    }

    func testDismissBeforeTheSelectionArrivesRejectsTheLateResult() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        await waitUntil { f.surfaces.events == ["show editor"] }
        f.controller.send(.dismiss)
        XCTAssertFalse(f.controller.isOpen)

        await f.selectionGate.open(selection)
        await Task.yield()
        XCTAssertNil(f.controller.captured)
        XCTAssertEqual(f.surfaces.events, ["show editor", "close"])
    }

    func testModeChangeMidCaptureCancelsIt() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        await waitUntil { f.recorder.starts == 1 }
        f.controller.send(.voiceModeChanged(.tap))
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.recorder.discards, 1)
        XCTAssertEqual(f.controller.state.voice, VoiceGesture(mode: .tap))
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
    }

    func testTeardownClosesDiscardsAndIgnoresEverythingAfter() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        await waitUntil { f.surfaces.events == ["show editor"] }
        f.controller.teardown()
        f.controller.teardown()
        XCTAssertEqual(f.surfaces.events, ["show editor", "close", "discard"])
        XCTAssertTrue(f.controller.state.isTornDown)

        f.controller.beginCapture()
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.surfaces.events.count, 3)
        XCTAssertEqual(f.recorder.starts, 0)
        await f.selectionGate.open(selection)
    }
}
