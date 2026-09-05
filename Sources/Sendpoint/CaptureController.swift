import AppKit
import Observation
import SendpointDomain

/// Replace these leaves in tests; no microphone, clipboard or windows are required.
@MainActor
struct CaptureServices {
    var selection: (CaptureMode) async throws -> CapturedSelection
    var startRecording: () async throws -> Void
    var transcribe: () async throws -> String
    var discardRecording: () -> Void

    static var live: Self {
        Self(selection: { try await SelectionCapture.capture(fallback: $0 == .text ? .patient : .brief) },
            startRecording: {
                guard await VoiceAnnotationService.shared.requestMicrophoneAccess() else {
                    throw CaptureServiceError.microphoneDenied
                }
                try Task.checkCancellation()
                try VoiceAnnotationService.shared.startRecording()
            },
            transcribe: { try await VoiceAnnotationService.shared.stopAndTranscribe() },
            discardRecording: { VoiceAnnotationService.shared.discardRecording() })
    }
}

private enum CaptureServiceError: LocalizedError {
    case microphoneDenied
    var errorDescription: String? { "Microphone access is off. Turn it on in Settings › Voice." }
}

enum CaptureSurface { case editor, voice }

@MainActor
struct CapturePresentation {
    var show: (CaptureSurface) -> Void
    var focus: () -> Void
    var close: () -> Void
    var stopEscapeHandling: () -> Void
}

/// TEA effect owner. The reducer owns workflow state; this owns native resources.
@MainActor
@Observable
final class CaptureController {
    private(set) var state: CaptureState = .idle
    @ObservationIgnored private var store: AnnotationStore?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let permissionState: PermissionState
    @ObservationIgnored private let services: CaptureServices
    @ObservationIgnored private let presentation: CapturePresentation?
    @ObservationIgnored private lazy var windows = CaptureWindows(model: self)
    @ObservationIgnored private var previousApp: NSRunningApplication?
    private enum Work: Hashable { case selection, recording, transcription, failure }
    @ObservationIgnored private var tasks: [Work: Task<Void, Never>] = [:]
    @ObservationIgnored private let probe: ProvenanceProbe
    @ObservationIgnored private lazy var provenance = PendingProvenanceWorkOwner(
        probe: probe, lateUpdate: { [weak self] mutation in self?.store?.mutate(mutation) })

    var onAccessibilityRequired: (() -> Void)?
    var onStatusChange: (() -> Void)?
    var onVoiceCaptureEnded: (() -> Void)?
    var onVoiceEscape: (() -> Void)?

    var levelMeter: VoiceLevelMeter { VoiceAnnotationService.shared.levelMeter }
    var isOpen: Bool { state.session != nil }
    var captured: CapturedSelection? { state.session?.target?.captured }
    var note: String {
        get {
            switch state.session?.phase {
            case let .editing(note): return note
            case let .saving(request), let .saveFailed(request, _, _, _): return request.annotation.note
            default: return ""
            }
        }
        set { send(.changeNote(newValue)) }
    }
    var isNoteFrozen: Bool {
        if case .editing = state.session?.phase { return false }
        return true
    }

    init(settings: AppSettings, permissionState: PermissionState,
         provenanceProbe: ProvenanceProbe = .live(), services: CaptureServices? = nil,
         presentation: CapturePresentation? = nil) {
        self.settings = settings
        self.permissionState = permissionState
        self.probe = provenanceProbe
        self.services = services ?? .live
        self.presentation = presentation
    }

    func configure(store: AnnotationStore) {
        guard state != .tornDown else { return }
        precondition(self.store == nil || self.store === store)
        self.store = store
    }

    func beginCapture() { begin(.text) }
    func beginVoiceCapture() { begin(.voice) }
    func endVoiceCapture() { send(.finishVoice) }
    func cancelVoiceCapture() { send(.cancelVoice) }
    func voiceEscape() {
        if let onVoiceEscape { onVoiceEscape() } else { send(.cancelVoice) }
    }
    func saveToCurrentSession() {
        if let store { send(.retarget(store.currentSessionID)) }
    }

    private func begin(_ mode: CaptureMode) {
        guard state != .tornDown else { return }
        guard let store, !store.isTornDown else {
            NSSound.beep()
            if mode == .voice { onVoiceCaptureEnded?() }
            return
        }
        guard permissionState.isTextCaptureReady else {
            onAccessibilityRequired?()
            if mode == .voice { onVoiceCaptureEnded?() }
            return
        }
        let wasOpen = isOpen
        if !wasOpen { previousApp = NSWorkspace.shared.frontmostApplication }
        send(.begin(mode, AnnotationCaptureContext(sessionID: store.currentSessionID)))
        if wasOpen && mode == .voice { onVoiceCaptureEnded?() }
    }

    func send(_ action: CaptureAction) {
        let previous = state.session
        let effects = state.update(action)
        for effect in effects { run(effect, previous: previous) }
        onStatusChange?()
    }

    private func run(_ effect: CaptureEffect, previous: CaptureSession?) {
        switch effect {
        case let .readSelection(context, mode):
            launch(.selection, context: context) { [services] in
                .selection(context, try await services.selection(mode))
            }
        case let .startRecording(context):
            launch(.recording, context: context) { [services] in
                try await services.startRecording()
                return .recordingStarted(context)
            }
        case let .transcribe(context):
            if let presentation { presentation.stopEscapeHandling() } else { windows.stopEscapeHandling() }
            launch(.transcription, context: context) { [services] in
                .transcript(context, try await services.transcribe())
            }
        case let .probe(target): provenance.start(for: target)
        case let .save(request):
            let annotation = provenance.annotationForSave(request.annotation, target: request.target)
            send(.prepared(request, annotation))
        case let .commit(request):
            guard let store else { return }
            store.mutate(.addAnnotation(sessionID: request.destinationSessionID, annotation: request.annotation)) {
                [weak self, weak store] outcome in
                guard let self, self.state != .tornDown else { return }
                switch outcome {
                case .noOp, .rejected, .cancelled: self.provenance.abandon(for: request.target)
                case .committed, .commitFailed: break
                }
                self.send(.saved(request, outcome, destinationExists: store?.sessions.contains {
                    $0.id == request.destinationSessionID
                } ?? false))
            }
        case .retry: store?.retryPendingMutations()
        case let .abandon(target): provenance.abandon(for: target)
        case .showEditor, .showVoice:
            let surface: CaptureSurface
            if case .showEditor = effect { surface = .editor } else { surface = .voice }
            if let presentation { presentation.show(surface) } else { windows.show(surface) }
        case .focusEditor:
            if let presentation { presentation.focus() } else { windows.focus() }
        case let .failureTimer(context):
            cancelWork()
            launch(.failure, context: context) {
                try await Task.sleep(for: .seconds(2.5))
                return .failureTimeout(context)
            }
        case .close:
            cancelWork()
            if let presentation { presentation.close() } else { windows.close() }
            if state != .tornDown, settings.restoreFocusAfterSave,
               let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp.activate()
            }
            previousApp = nil
            if previous?.mode == .voice { onVoiceCaptureEnded?() }
        case .beep: NSSound.beep()
        }
    }

    private func launch(_ work: Work, context: AnnotationCaptureContext,
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
        services.discardRecording()
    }

    func teardown() {
        guard state != .tornDown else { return }
        onVoiceCaptureEnded = nil
        send(.teardown)
        provenance.teardown()
        store = nil
        onAccessibilityRequired = nil
        onStatusChange = nil
        onVoiceEscape = nil
    }
}
