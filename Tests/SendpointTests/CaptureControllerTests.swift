import Foundation
import Observation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class CaptureControllerTests: XCTestCase {
    @Observable @MainActor final class Surfaces {
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

    @MainActor private final class Pasteboard {
        var inserted: [(String, pid_t)] = []
        var pasteSucceeds = true
    }

    private struct Fixture {
        let controller: CaptureController
        let store: StackStore
        let surfaces: Surfaces
        let recorder: FakeVoiceRecorder
        let pasteboard: Pasteboard
        let selectionGate: Gate<CapturedSelection>
        let selectionStarted: AsyncAcknowledgement
        let selectionReturned: AsyncAcknowledgement
        let voiceOutputs: AsyncAcknowledgement
        let timing: ControlledSleep
        var accessibilityRequests = 0
    }

    private let selection = CapturedSelection(text: "A passage")
    private let frontApp = DictationTarget(processIdentifier: 7, appName: "Safari")

    private func makeFixture(
        accessibility: AccessibilityPermissionState = .granted,
        hasFrontApp: Bool = true,
        sleep: (@MainActor (Duration) async throws -> Void)? = nil,
        diagnostics: @escaping DiagnosticSink = { _ in }
    ) async throws -> Fixture {
        let suite = "CaptureControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "restoreFocusAfterSave")
        let permissions = PermissionController(services: PermissionServices(
            accessibilityStatus: { accessibility }, requestAccessibility: { true },
            microphoneStatus: { .granted }, requestMicrophone: { true },
            voiceModelFilesExist: { true }, downloadVoiceModel: { _ in },
            openAccessibilitySettings: {}, openMicrophoneSettings: {}
        ))
        let store = try await StackStore(persistence: StorePersistence(load: { nil }, commit: { _ in }),
                                        diagnostics: diagnostics)
        let surfaces = Surfaces()
        let recorder = FakeVoiceRecorder()
        let pasteboard = Pasteboard()
        let gate = Gate<CapturedSelection>()
        let selectionReturned = AsyncAcknowledgement()
        let selectionStarted = AsyncAcknowledgement()
        let voiceOutputs = AsyncAcknowledgement()
        let timing = ControlledSleep()
        var recorderBoundary = recorder.boundary
        let observe = recorderBoundary.observe
        recorderBoundary.observe = { receive in
            observe { output in
                receive(output)
                voiceOutputs.signal()
            }
        }
        let frontApp = hasFrontApp ? self.frontApp : nil
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults),
            voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: permissions,
            selection: SelectionCapture(
                read: { _, editorMayOpen in
                    defer { selectionReturned.signal() }
                    selectionStarted.signal()
                    editorMayOpen()
                    return await gate.wait()
                },
                paste: { _, _ in false },
                insertText: { text, pid in
                    pasteboard.inserted.append((text, pid))
                    return pasteboard.pasteSucceeds
                }
            ),
            recorder: recorderBoundary,
            frontApp: { frontApp },
            sleep: sleep ?? { try await timing.sleep($0) },
            diagnostics: diagnostics,
            surfaces: { _ in surfaces.boundary }
        )
        controller.configure(store: store)
        addTeardownBlock { @MainActor in
            controller.teardown()
            await gate.open(CapturedSelection(text: ""))
            await recorder.started.open(true)
            store.teardown()
            defaults.removePersistentDomain(forName: suite)
        }
        return Fixture(controller: controller, store: store, surfaces: surfaces,
                       recorder: recorder, pasteboard: pasteboard, selectionGate: gate,
                       selectionStarted: selectionStarted, selectionReturned: selectionReturned,
                       voiceOutputs: voiceOutputs, timing: timing)
    }

    func testCaptureSaveExportDiagnosticsJoinByNoteWithoutPrivateContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("records.jsonl")
        let journal = DiagnosticJournal(file: file)
        let f = try await makeFixture(diagnostics: journal.record)
        f.controller.beginCapture()
        let context = try XCTUnwrap(f.controller.state.identity)
        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.captured == self.selection }
        f.controller.note = "PRIVATE body"
        f.controller.send(.save)
        await f.store.waitForIdle()
        var template = Template.plain
        template.clearStackAfterExport = true
        let exporter = ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in false }),
                                        diagnostics: journal.record)
        exporter.copy(store: f.store, stackID: context.sourceStack, template: template) { _ in }
        await f.store.waitForIdle()
        let bytes = try Data(contentsOf: file)
        let records = try bytes.split(separator: 0x0A).map { try JSONDecoder().decode(DiagnosticRecord.self, from: Data($0)) }
        XCTAssertTrue(records.contains(DiagnosticRecord(.capture, .accepted, operationID: context.noteID,
                                                        stackID: context.sourceStack, noteID: context.noteID)))
        XCTAssertTrue(records.contains(DiagnosticRecord(.save, .succeeded, operationID: context.noteID,
                                                        stackID: context.sourceStack, noteID: context.noteID)))
        let exported = try XCTUnwrap(records.first { $0.stage == .export && $0.noteID == context.noteID })
        XCTAssertTrue(records.contains(DiagnosticRecord(.cleanup, .succeeded, operationID: exported.operationID,
                                                        stackID: context.sourceStack, noteID: context.noteID)))
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE body"))
        XCTAssertFalse(text.contains("A passage"))
        XCTAssertTrue(f.store.currentNotes.isEmpty)
    }

    func testTypedNoteOpensTheEditorEarlyThenSavesAndCloses() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        XCTAssertEqual(f.surfaces.events, [], "nothing shows until the reader lets go of the front app")
        await waitForObservation { f.surfaces.events == ["show editor"] }
        XCTAssertEqual(f.controller.captured, nil)

        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.captured == self.selection }
        f.controller.note = "A thought"
        f.controller.send(.save)
        await f.store.waitForIdle()
        await waitForObservation { !f.controller.isOpen }

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
        await waitForObservation { f.surfaces.events == ["show editor"] }
        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.captured == self.selection }
        let context = try XCTUnwrap(f.controller.state.identity)
        f.controller.note = "Filed elsewhere"
        f.controller.send(.toggleDestinations(context))
        f.controller.chooseDestination(destination.id, context: context)

        XCTAssertEqual(f.controller.targetStack?.id, destination.id)
        XCTAssertEqual(f.controller.note, "Filed elsewhere")
        XCTAssertEqual(f.controller.captured, selection)
        f.controller.send(.save)
        await f.store.waitForIdle()
        await waitForObservation { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentStackID, destination.id)
        XCTAssertTrue(f.store.stack(id: sourceID).notes.isEmpty)
        XCTAssertEqual(f.store.stack(id: destination.id).notes.map(\.body), ["Filed elsewhere"])
        XCTAssertEqual(f.store.stack(id: destination.id).notes.first?.subject,
            .selection(quote: "A passage"))
    }

    func testDestinationChoiceFromEitherModeBecomesCurrentForBothSubsequentModes() async throws {
        for surface in [CaptureSurface.editor, .voice] {
            let f = try await makeFixture()
            let destination = f.store.stacks[1]
            await f.selectionGate.open(selection)
            await f.recorder.started.open(true)

            if surface == .editor { f.controller.beginCapture() }
            else { f.controller.send(.voiceToggled) }
            await waitForObservation { f.controller.state.destination?.canChoose == true }
            let context = try XCTUnwrap(f.controller.state.identity)
            f.controller.send(.toggleDestinations(context))
            f.controller.chooseDestination(destination.id, context: context)
            await f.store.waitForIdle()
            XCTAssertEqual(f.store.currentStackID, destination.id)
            XCTAssertEqual(StackUIFacts(store: f.store).currentStackID, destination.id)

            f.controller.send(surface == .editor ? .dismiss : .cancelVoice)
            f.controller.beginCapture()
            XCTAssertEqual(f.controller.state.destination?.slot, destination.id)
            f.controller.send(.dismiss)
            f.controller.send(.voiceToggled)
            XCTAssertEqual(f.controller.state.destination?.slot, destination.id)
            f.controller.teardown()
        }
    }

    func testACaptureStillChoosingFollowsAStackShortcutButASaveInFlightDoesNot() async throws {
        let f = try await makeFixture()
        let sourceID = f.store.currentStackID
        let destination = f.store.stacks[2]
        await f.selectionGate.open(selection)

        f.controller.send(.stackSelected(destination.id))
        XCTAssertNil(f.controller.state.identity, "no capture, nothing to follow")

        f.controller.beginCapture()
        await waitForObservation { f.controller.captured == self.selection }
        let context = try XCTUnwrap(f.controller.state.identity)
        f.controller.send(.toggleDestinations(context))
        f.controller.send(.stackSelected(destination.id))

        XCTAssertEqual(f.controller.state.destination?.slot, destination.id)
        XCTAssertEqual(f.controller.state.destination?.isPickerOpen, false)
        XCTAssertEqual(f.store.currentStackID, sourceID, "the shortcut's owner does the switch, not the capture")

        f.controller.note = "Lands in the third stack"
        f.controller.send(.save)
        f.controller.send(.stackSelected(sourceID))
        await f.store.waitForIdle()
        await waitForObservation { !f.controller.isOpen }

        XCTAssertEqual(f.store.stack(id: destination.id).notes.map(\.body), ["Lands in the third stack"])
        XCTAssertTrue(f.store.stack(id: sourceID).notes.isEmpty)
    }

    func testRejectedDestinationChoicesDoNotChangeTheCurrentStack() async throws {
        let f = try await makeFixture()
        let sourceID = f.store.currentStackID
        let destination = f.store.stacks[1]
        await f.selectionGate.open(selection)
        f.controller.beginCapture()
        let context = try XCTUnwrap(f.controller.state.identity)
        f.controller.chooseDestination(destination.id, context: context)
        f.controller.send(.toggleDestinations(context))
        f.controller.chooseDestination(destination.id, context: CaptureIdentity(sourceStack: sourceID))
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
        XCTAssertEqual(f.recorder.starts, 1)
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.state.speech?.stage == .listening }

        f.controller.send(.voiceReleased)
        await f.store.waitForIdle()
        await waitForObservation { !f.controller.isOpen }

        XCTAssertEqual(f.store.currentNotes.map(\.body), ["hello there"])
        XCTAssertEqual(f.recorder.discards, 1, "closing releases the microphone once")
        XCTAssertEqual(f.controller.state.speechLatch, .up)
    }

    func testDictationHoldPastesTheTranscriptIntoTheFrontAppAndSavesNothing() async throws {
        let f = try await makeFixture()
        f.controller.send(.dictatePressed)
        XCTAssertEqual(f.surfaces.events, ["show voice"])
        XCTAssertEqual(f.controller.state.speech?.origin, .dictation(frontApp))
        XCTAssertEqual(f.recorder.starts, 1)
        await f.recorder.started.open(true)
        await waitForObservation { f.controller.state.speech?.stage == .listening }

        f.controller.send(.dictateReleased)
        await waitForObservation { !f.controller.isOpen }

        XCTAssertEqual(f.pasteboard.inserted.map(\.0), ["hello there"])
        XCTAssertEqual(f.pasteboard.inserted.map(\.1), [7])
        XCTAssertTrue(f.store.currentNotes.isEmpty, "dictation never touches the stack")
        XCTAssertEqual(f.recorder.discards, 1)
        XCTAssertEqual(f.controller.state.speechLatch, .up)
    }

    func testDictationWithNoFrontAppIsRefusedUntilTheKeyComesUp() async throws {
        let f = try await makeFixture(hasFrontApp: false)
        f.controller.send(.dictatePressed)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events, [])
        XCTAssertEqual(f.controller.state.speechLatch, .consumeRelease(.dictate))
        f.controller.send(.dictatePressed)
        XCTAssertFalse(f.controller.isOpen, "still down")
        f.controller.send(.dictateReleased)
        XCTAssertEqual(f.controller.state.speechLatch, .up)
    }

    func testAFailedPasteShowsAMessageAndCloses() async throws {
        let f = try await makeFixture()
        f.pasteboard.pasteSucceeds = false
        f.controller.send(.dictatePressed)
        XCTAssertEqual(f.recorder.starts, 1)
        await f.recorder.started.open(true)
        await waitForObservation { f.controller.state.speech?.stage == .listening }
        f.controller.send(.dictateReleased)
        await waitForObservation { f.controller.state.speech?.stage == .failed("Couldn’t paste.") }
        XCTAssertEqual(f.pasteboard.inserted.count, 1)
        XCTAssertTrue(f.store.currentNotes.isEmpty)
        f.controller.send(.voiceEscape)
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events.last, "close")
    }

    func testReleaseBeforeTheMicrophoneOpensEndsQuietly() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.recorder.starts, 1)
        await f.selectionStarted.wait()
        f.controller.send(.voiceReleased)

        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.surfaces.events, ["show voice", "close"])
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
        await f.voiceOutputs.wait()
        await f.selectionReturned.wait()
        XCTAssertFalse(f.controller.isOpen, "late results find no capture")
        XCTAssertTrue(f.store.currentNotes.isEmpty)
    }

    func testEscapeDuringRecordingDiscardsTheClip() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.recorder.starts, 1)
        await f.recorder.started.open(true)
        await waitForObservation { f.controller.state.speech?.stage == .listening }

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
        await waitForObservation { failing.controller.state.speech?.stage == .failed("mic busy") }
        XCTAssertEqual(failing.recorder.discards, 1)
        failing.controller.send(.voiceEscape)
        XCTAssertFalse(failing.controller.isOpen)
        await failing.selectionGate.open(selection)

        let silent = try await makeFixture()
        silent.recorder.transcript = .success("   ")
        silent.controller.send(.voicePressed)
        XCTAssertEqual(silent.recorder.starts, 1)
        await silent.recorder.started.open(true)
        await silent.selectionGate.open(selection)
        await waitForObservation { silent.controller.state.speech?.stage == .listening }
        silent.controller.send(.voiceReleased)
        await waitForObservation { !silent.controller.isOpen }
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

    func testVoiceSelectionDeadlineSavesWithoutWaitingForTheReader() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        await f.recorder.started.open(true)
        await f.voiceOutputs.wait()
        await f.selectionStarted.wait()
        f.controller.send(.voiceReleased)
        await f.timing.started.wait()
        XCTAssertEqual(f.timing.durations, [CaptureController.selectionDeadline])
        XCTAssertTrue(f.controller.isOpen)
        f.timing.advance(CaptureController.selectionDeadline)
        await waitForObservation { !f.controller.isOpen }
        XCTAssertEqual(f.store.currentNotes.map(\.body), ["hello there"])
        await f.selectionGate.open(selection)
        await f.selectionReturned.wait()
        f.controller.teardown()
    }

    func testFailureTimerClosesOnlyAfterItsInjectedDelay() async throws {
        let f = try await makeFixture()
        f.recorder.startFails = true
        f.controller.send(.voicePressed)
        await f.timing.started.wait()
        XCTAssertEqual(f.controller.state.speech?.stage, .failed("mic busy"))
        XCTAssertEqual(f.timing.durations, [.seconds(2.5)])
        f.timing.advance(.seconds(2.5))
        await waitForObservation { !f.controller.isOpen }
        XCTAssertEqual(f.surfaces.events.last, "close")
        await f.selectionGate.open(selection)
        f.controller.teardown()
    }

    func testDismissCancelsTheFailureTimerBeforeAnotherCaptureBegins() async throws {
        let f = try await makeFixture()
        f.recorder.startFails = true
        f.controller.send(.voicePressed)
        await f.timing.started.wait()
        f.controller.send(.voiceEscape)
        await f.timing.completed.wait()
        f.controller.beginCapture()
        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.captured == self.selection }
        f.timing.advance(.seconds(2.5))
        XCTAssertTrue(f.controller.isOpen)
        f.controller.teardown()
    }

    func testCancelledDeadlineCannotCancelANewSelectionEvenWhenSleepIgnoresCancellation() async throws {
        let gate = Gate<Bool>()
        let started = AsyncAcknowledgement()
        let returned = AsyncAcknowledgement()
        let f = try await makeFixture(sleep: { _ in
            defer { returned.signal() }
            started.signal()
            _ = await gate.wait()
        })
        f.controller.send(.voicePressed)
        await f.recorder.started.open(true)
        await f.voiceOutputs.wait()
        await f.selectionStarted.wait()
        f.controller.send(.voiceReleased)
        await started.wait()
        f.controller.send(.cancelVoice)
        f.controller.beginCapture()
        await f.selectionStarted.wait(for: 2)
        await gate.open(true)
        await returned.wait()
        await f.selectionGate.open(selection)
        await waitForObservation { f.controller.captured == self.selection }
        XCTAssertTrue(f.controller.isOpen)
        f.controller.teardown()
    }

    func testDismissBeforeTheSelectionArrivesRejectsTheLateResult() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        await waitForObservation { f.surfaces.events == ["show editor"] }
        f.controller.send(.dismiss)
        XCTAssertFalse(f.controller.isOpen)

        await f.selectionGate.open(selection)
        await f.selectionReturned.wait()
        XCTAssertNil(f.controller.captured)
        XCTAssertEqual(f.surfaces.events, ["show editor", "close"])
    }

    func testModeChangeMidCaptureCancelsIt() async throws {
        let f = try await makeFixture()
        f.controller.send(.voicePressed)
        XCTAssertEqual(f.recorder.starts, 1)
        f.controller.send(.voiceModeChanged(.tap))
        XCTAssertFalse(f.controller.isOpen)
        XCTAssertEqual(f.recorder.discards, 1)
        XCTAssertEqual(f.controller.state.voiceMode, .tap)
        await f.recorder.started.open(true)
        await f.selectionGate.open(selection)
    }

    func testTeardownClosesDiscardsAndIgnoresEverythingAfter() async throws {
        let f = try await makeFixture()
        f.controller.beginCapture()
        await waitForObservation { f.surfaces.events == ["show editor"] }
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
