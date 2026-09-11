import AppKit
import Observation
import SendpointDomain

/// The microphone and recogniser behind a voice note. Tests substitute closures.
struct VoiceRecorder {
    /// Asks for microphone access if needed, then starts recording.
    var start: () async throws -> Void
    var stopAndTranscribe: () async throws -> String
    var discard: () -> Void
    var levelMeter: VoiceLevelMeter

    static func live(_ service: VoiceNoteService) -> Self {
        Self(
            start: {
                guard await service.requestMicrophoneAccess() else {
                    throw VoiceRecorderError.microphoneDenied
                }
                try Task.checkCancellation()
                try service.startRecording()
            },
            stopAndTranscribe: { try await service.stopAndTranscribe() },
            discard: { service.discardRecording() },
            levelMeter: service.levelMeter
        )
    }
}

private enum VoiceRecorderError: LocalizedError {
    case microphoneDenied
    var errorDescription: String? { "Microphone access is off. Turn it on in Settings › Voice." }
}

/// The windows a capture shows. Tests record the calls instead of opening panels.
struct CaptureSurfaces {
    var prepare: () -> Void
    var show: (CaptureSurface) -> Void
    var focus: () -> Void
    var stopEscapeHandling: () -> Void
    var close: () -> Void
    var discard: () -> Void

    static func live(_ windows: CaptureWindows) -> Self {
        Self(
            prepare: { windows.prepareSurfaces() },
            show: { windows.show($0) },
            focus: { windows.focus() },
            stopEscapeHandling: { windows.stopEscapeHandling() },
            close: { windows.close() },
            discard: { windows.discardSurfaces() }
        )
    }
}

/// TEA effect owner. The reducer owns workflow state; this owns native resources.
@Observable
final class CaptureController {
    private(set) var state = CaptureState()
    @ObservationIgnored private var store: StackStore?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let permissionState: PermissionState
    @ObservationIgnored private let selection: SelectionCapture
    @ObservationIgnored private let recorder: VoiceRecorder
    @ObservationIgnored private let makeSurfaces: (CaptureController) -> CaptureSurfaces
    @ObservationIgnored private lazy var surfaces = makeSurfaces(self)
    @ObservationIgnored private var previousApp: NSRunningApplication?
    /// Actions sent while one is being applied wait their turn, so an effect
    /// never sees state from halfway through another action.
    @ObservationIgnored private var pending: [CaptureAction] = []
    @ObservationIgnored private var isDraining = false
    private enum Work: Hashable { case selection, recording, transcription, failure }
    @ObservationIgnored private var tasks: [Work: Task<Void, Never>] = [:]
    @ObservationIgnored private let probe: ProvenanceProbe
    @ObservationIgnored private lazy var provenance = PendingProvenanceWorkOwner(
        probe: probe, lateUpdate: { [weak self] mutation in self?.store?.mutate(mutation) })

    var onAccessibilityRequired: (() -> Void)?
    var onStatusChange: (() -> Void)?

    var levelMeter: VoiceLevelMeter { recorder.levelMeter }
    /// The stack this note lands in: the one fixed when the capture began,
    /// so switching stacks mid-note does not change what the pill says.
    var targetStack: StackItemFacts? {
        guard let store else { return nil }
        let id = state.session?.context.stackID ?? store.currentStackID
        return StackUIFacts(stacks: store.stacks, currentStackID: store.currentStackID,
            lastCleared: store.lastCleared).stack(id: id)
    }
    var isOpen: Bool { state.session != nil }
    var captured: CapturedSelection? { state.session?.target?.captured }
    var note: String {
        get {
            switch state.session?.phase {
            case let .editing(note): return note
            case let .saving(request), let .saveFailed(request, _, _, _): return request.note.body
            default: return ""
            }
        }
        set { send(.changeNote(newValue)) }
    }
    var isNoteFrozen: Bool {
        guard let session = state.session, case .editing = session.phase else { return true }
        return session.saveAwaitsSelection
    }

    init(settings: AppSettings, permissionState: PermissionState,
         selection: SelectionCapture, recorder: VoiceRecorder,
         provenanceProbe: ProvenanceProbe = .live(),
         surfaces: @escaping (CaptureController) -> CaptureSurfaces = {
             .live(CaptureWindows(model: $0, surfaces: SurfaceCoordinator()))
         }) {
        self.settings = settings
        self.permissionState = permissionState
        self.selection = selection
        self.recorder = recorder
        self.probe = provenanceProbe
        self.makeSurfaces = surfaces
    }

    func configure(store: StackStore) {
        guard !state.isTornDown else { return }
        precondition(self.store == nil || self.store === store)
        self.store = store
    }

    /// Builds the overlay and the note box ahead of the first hotkey press.
    func warmUp() {
        guard !state.isTornDown else { return }
        surfaces.prepare()
    }

    func beginCapture() {
        if let context = beginContext() { send(.begin(.text, context)) }
    }

    func saveToCurrentStack() {
        if let store { send(.retarget(store.currentStackID)) }
    }

    /// What a capture needs before the reducer sees it. A refusal is reported
    /// here, once, and the reducer hears nothing.
    private func beginContext() -> NoteCaptureContext? {
        guard !state.isTornDown else { return nil }
        guard let store, store.state != .tornDown else {
            NSSound.beep()
            return nil
        }
        guard permissionState.isTextCaptureReady else {
            onAccessibilityRequired?()
            return nil
        }
        if !isOpen { previousApp = NSWorkspace.shared.frontmostApplication }
        return NoteCaptureContext(stackID: store.currentStackID)
    }

    func send(_ action: CaptureAction) {
        pending.append(action)
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            let previous = state.session
            for effect in state.update(pending.removeFirst()) { run(effect, previous: previous) }
        }
        isDraining = false
        onStatusChange?()
    }

    private func run(_ effect: CaptureEffect, previous: CaptureSession?) {
        switch effect {
        case .beginVoice:
            if let context = beginContext() { send(.begin(.voice, context)) } else { send(.voiceRefused) }
        case let .readSelection(context, mode):
            launch(.selection, context: context) { [selection, weak self] in
                .selection(context, try await selection.read(mode == .text ? .patient : .brief) {
                    self?.send(.selectionPending(context))
                })
            }
        case let .startRecording(context):
            launch(.recording, context: context) { [recorder] in
                try await recorder.start()
                return .recordingStarted(context)
            }
        case let .transcribe(context):
            surfaces.stopEscapeHandling()
            launch(.transcription, context: context) { [recorder] in
                .transcript(context, try await recorder.stopAndTranscribe())
            }
        case let .probe(target): provenance.start(for: target)
        case let .save(request):
            let note = provenance.noteForSave(request.note, target: request.target)
            send(.prepared(request, note))
        case let .commit(request):
            guard let store else { return }
            store.mutate(.addNote(stackID: request.destinationStackID, note: request.note)) {
                [weak self, weak store] outcome in
                guard let self, !self.state.isTornDown else { return }
                switch outcome {
                case .noOp, .rejected, .cancelled: self.provenance.abandon(for: request.target)
                case .committed, .commitFailed: break
                }
                self.send(.saved(request, outcome, destinationExists: store?.stacks.contains {
                    $0.id == request.destinationStackID
                } ?? false))
            }
        case .retry: store?.retryPendingMutations()
        case let .abandon(target): provenance.abandon(for: target)
        case let .show(surface): surfaces.show(surface)
        case .focusEditor: surfaces.focus()
        case let .failureTimer(context):
            cancelWork()
            launch(.failure, context: context) {
                try await Task.sleep(for: .seconds(2.5))
                return .failureTimeout(context)
            }
        case .close:
            cancelWork()
            surfaces.close()
            if !state.isTornDown, settings.restoreFocusAfterSave,
               let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp.activate()
            }
            previousApp = nil
        case .beep: NSSound.beep()
        }
    }

    private func launch(_ work: Work, context: NoteCaptureContext,
                        operation: @escaping @MainActor () async throws -> CaptureAction) {
        guard state.session?.context == context else { return }
        tasks[work]?.cancel()
        tasks[work] = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let action = try await operation()
                try Task.checkCancellation()
                guard let self, self.state.session?.context == context else { return }
                self.tasks[work] = nil
                self.send(action)
            } catch is CancellationError {
                // Cancellation and resource release belong to cancelWork().
            } catch {
                guard !Task.isCancelled, let self, self.state.session?.context == context else { return }
                self.tasks[work] = nil
                self.send(.failed(context, error.localizedDescription))
            }
        }
    }

    private func cancelWork() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        recorder.discard()
    }

    func teardown() {
        guard !state.isTornDown else { return }
        send(.teardown)
        surfaces.discard()
        provenance.teardown()
        store = nil
        onAccessibilityRequired = nil
        onStatusChange = nil
    }
}
