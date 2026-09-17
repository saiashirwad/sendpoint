import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

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

    @MainActor private final class Pasteboard {
        var inserted: [(String, pid_t)] = []
        var pasteSucceeds = true
    }

    private struct Fixture {
        let controller: CaptureController
        let store: StackStore
        let surfaces: Surfaces
        let recorder: Recorder
        let pasteboard: Pasteboard
        let selectionGate: Gate<CapturedSelection>
        var accessibilityRequests = 0
    }

    private let selection = CapturedSelection(text: "A passage")
    private let frontApp = DictationTarget(processIdentifier: 7, appName: "Safari")

    private func makeFixture(
        accessibility: AccessibilityPermissionState = .granted,
        hasFrontApp: Bool = true
    ) async throws -> Fixture {
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
        let pasteboard = Pasteboard()
        let gate = Gate<CapturedSelection>()
        let frontApp = hasFrontApp ? self.frontApp : nil
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults),
            voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: permissions,
            selection: SelectionCapture(
                read: { _, editorMayOpen in
                    editorMayOpen()
                    return await gate.wait()
                },
                paste: { _, _ in false },
                insertText: { text, pid in
                    pasteboard.inserted.append((text, pid))
                    return pasteboard.pasteSucceeds
                }
            ),
            recorder: recorder.boundary,
            frontApp: { frontApp },
            surfaces: { _ in surfaces.boundary }
        )
        controller.configure(store: store)
        return Fixture(controller: controller, store: store, surfaces: surfaces,
                       recorder: recorder, pasteboard: pasteboard, selectionGate: gate)
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

    func testTypedNoteSavesToTheChosenDestinationAndSwitchesTheCurrentStack() async throws {
        let f = try await makeFixture()
        let sourceID = f.store.currentStackID
        let destination = f.store.stacks[1]
        XCTAssertEqual(f.store.currentStackID, sourceID)

        f.controller.beginCapture()
        await waitUntil { f.surfaces.events == ["show editor"] }
        await f.selectionGate.open(selection)
        await waitUntil { f.controller.captured == self.selection }
        let context = try XCTUnwrap(f.controller.state.session?.context)
        f.controller.note = "Filed elsewhere"
        f.controller.send(.toggleDestinations(context))
        f.controller.chooseDestination(destination.id, context: context)

        XCTAssertEqual(f.controller.targetStack?.id, destination.id)
        XCTAssertEqual(f.controller.note, "Filed elsewhere")
        XCTAssertEqual(f.controller.captured, selection)
        f.controller.send(.save)
        await f.store.waitForIdle()
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentStackID, destination.id)
        XCTAssertTrue(f.store.stack(id: sourceID)?.notes.isEmpty == true)
        XCTAssertEqual(f.store.stack(id: destination.id)?.notes.map(\.body), ["Filed elsewhere"])
        XCTAssertEqual(f.store.stack(id: destination.id)?.notes.first?.subject,
            .selection(quote: "A passage"))
    }

    func testDestinationChoiceFromEitherModeBecomesCurrentForBothSubsequentModes() async throws {
        for mode in [CaptureMode.text, .voice] {
            let f = try await makeFixture()
            let sourceID = f.store.currentStackID
            let destination = f.store.stacks[1]
            await f.selectionGate.open(selection)
            await f.recorder.started.open(true)

            if mode == .text { f.controller.beginCapture() }
            else { f.controller.send(.voiceToggled) }
            await waitUntil { f.controller.state.session?.canChooseDestination == true }
            let context = try XCTUnwrap(f.controller.state.session?.context)
            f.controller.send(.toggleDestinations(context))
            f.controller.chooseDestination(destination.id, context: context)
            await f.store.waitForIdle()
            XCTAssertEqual(f.store.currentStackID, destination.id)
            XCTAssertEqual(StackUIFacts(store: f.store).currentStackID, destination.id)

            f.controller.send(mode == .text ? .dismiss : .cancelVoice)
            f.controller.beginCapture()
            XCTAssertEqual(f.controller.state.session?.destinationStackID, destination.id)
            f.controller.send(.dismiss)
            f.controller.send(.voiceToggled)
            XCTAssertEqual(f.controller.state.session?.destinationStackID, destination.id)
            f.controller.teardown()
        }
    }

    func testACaptureStillChoosingFollowsAStackShortcutButASaveInFlightDoesNot() async throws {
        let f = try await makeFixture()
        let sourceID = f.store.currentStackID
        let destination = f.store.stacks[2]
        await f.selectionGate.open(selection)

        f.controller.send(.stackSelected(destination.id))
        XCTAssertNil(f.controller.state.session, "no capture, nothing to follow")

        f.controller.beginCapture()
        await waitUntil { f.controller.captured == self.selection }
        let context = try XCTUnwrap(f.controller.state.session?.context)
        f.controller.send(.toggleDestinations(context))
        f.controller.send(.stackSelected(destination.id))

        XCTAssertEqual(f.controller.state.session?.destinationStackID, destination.id)
        XCTAssertEqual(f.controller.state.session?.destinationPicker, .closed)
        XCTAssertEqual(f.store.currentStackID, sourceID, "the shortcut's owner does the switch, not the capture")

        f.controller.note = "Lands in the third stack"
        f.controller.send(.save)
        f.controller.send(.stackSelected(sourceID))
        await f.store.waitForIdle()
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.store.stack(id: destination.id)?.notes.map(\.body), ["Lands in the third stack"])
        XCTAssertTrue(f.store.stack(id: sourceID)?.notes.isEmpty == true)
    }

    func testRejectedDestinationChoicesDoNotChangeTheCurrentStack() async throws {
        let f = try await makeFixture()
        let sourceID = f.store.currentStackID
        let destination = f.store.stacks[1]
        await f.selectionGate.open(selection)
        f.controller.beginCapture()
        let context = try XCTUnwrap(f.controller.state.session?.context)
        f.controller.chooseDestination(destination.id, context: context)
        f.controller.send(.toggleDestinations(context))
        f.controller.chooseDestination(destination.id, context: NoteCaptureContext(stackID: sourceID))
        f.controller.chooseDestination(UUID(), context: context)
        f.controller.send(.dismiss)
        f.controller.chooseDestination(destination.id, context: context)
        await f.store.waitForIdle()
        XCTAssertEqual(f.store.currentStackID, sourceID)
        f.controller.teardown()
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
        await f.store.waitForIdle()
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentNotes.map(\.body), ["hello there"])
        XCTAssertEqual(f.recorder.discards, 1, "closing releases the microphone once")
        XCTAssertEqual(f.controller.state.voice, VoiceGesture())
    }

    func testDictationHoldPastesTheTranscriptIntoTheFrontAppAndSavesNothing() async throws {
        let f = try await makeFixture()
        f.controller.send(.dictatePressed)
        XCTAssertEqual(f.surfaces.events, ["show voice"])
        XCTAssertEqual(f.controller.state.session?.dictationTarget, frontApp)
        await waitUntil { f.recorder.starts == 1 }
        await f.recorder.started.open(true)
        await waitUntil { f.controller.state.session?.phase == .recording }

        f.controller.send(.dictateReleased)
        await waitUntil { !f.controller.isOpen }

        XCTAssertEqual(f.pasteboard.inserted.map(\.0), ["hello there"])
        XCTAssertEqual(f.pasteboard.inserted.map(\.1), [7])
        XCTAssertTrue(f.store.currentNotes.isEmpty, "dictation never touches the stack")
        XCTAssertEqual(f.recorder.discards, 1)
        XCTAssertEqual(f.controller.state.voice, VoiceGesture())
    }

    func testDictationWithNoFrontAppIsRefusedUntilTheKeyComesUp() async throws {
        let f = try await makeFixture(hasFrontApp: false)
        f.controller.send(.dictatePressed)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events, [])
        XCTAssertEqual(f.controller.state.voice, VoiceGesture(releasePending: true, key: .dictate))
        f.controller.send(.dictatePressed)
        XCTAssertFalse(f.controller.isOpen, "still down")
        f.controller.send(.dictateReleased)
        XCTAssertEqual(f.controller.state.voice, VoiceGesture())
    }

    func testAFailedPasteShowsAMessageAndCloses() async throws {
        let f = try await makeFixture()
        f.pasteboard.pasteSucceeds = false
        f.controller.send(.dictatePressed)
        await waitUntil { f.recorder.starts == 1 }
        await f.recorder.started.open(true)
        await waitUntil { f.controller.state.session?.phase == .recording }
        f.controller.send(.dictateReleased)
        await waitUntil { f.controller.state.session?.phase == .failed("Couldn’t paste.") }
        XCTAssertEqual(f.pasteboard.inserted.count, 1)
        XCTAssertTrue(f.store.currentNotes.isEmpty)
        f.controller.send(.voiceEscape)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events.last, "close")
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

    func testRecordingFailureShowsAMessageAndSilenceClosesQuietly() async throws {
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
        await waitUntil { !silent.controller.isOpen }
        XCTAssertEqual(silent.surfaces.events.last, "close")
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
