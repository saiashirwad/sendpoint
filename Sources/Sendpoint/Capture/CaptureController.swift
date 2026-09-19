import AppKit
import Observation
import SendpointDomain

struct VoiceRecorder {
    var start: (UUID) -> Void
    var stop: (UUID) -> Void
    var discard: () -> Void
    var levelMeter: VoiceLevelMeter
    var chooseMicrophone: (String?) -> Void = { _ in }
    var observe: (@escaping (VoiceOutput) -> Void) -> Void = { _ in }
    var warmUp: () -> Void = {}

    static func live(_ service: VoiceNoteService) -> Self {
        Self(
            start: { service.start($0) },
            stop: { service.stop($0) },
            discard: { service.discard() },
            levelMeter: service.levelMeter,
            chooseMicrophone: { service.preferredInputDeviceUID = $0 },
            observe: { service.onOutput = $0 },
            warmUp: { service.warmUp() }
        )
    }
}

struct CaptureSurfaces {
    var prepare: () -> Void
    var show: (CaptureSurface) -> Void
    var focus: () -> Void
    var close: () -> Void
    var discard: () -> Void

    static func live(_ windows: CaptureWindows) -> Self {
        Self(
            prepare: { windows.prepareSurfaces() },
            show: { windows.show($0) },
            focus: { windows.focus() },
            close: { windows.close() },
            discard: { windows.discardSurfaces() }
        )
    }
}

@Observable
final class CaptureController {
    private(set) var state = CaptureState()
    @ObservationIgnored private var store: StackStore?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let voiceSettings: VoiceSettings
    @ObservationIgnored private let permissionState: PermissionState
    @ObservationIgnored private let selection: SelectionCapture
    @ObservationIgnored private let recorder: VoiceRecorder
    @ObservationIgnored private let frontApp: @MainActor () -> DictationTarget?
    @ObservationIgnored private let makeSurfaces: (CaptureController) -> CaptureSurfaces
    @ObservationIgnored private lazy var surfaces = makeSurfaces(self)
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var pending: [CaptureAction] = []
    @ObservationIgnored private var isDraining = false
    private enum Work: Hashable { case selection, selectionDeadline, insertion, failure }
    @ObservationIgnored private var tasks: [Work: Task<Void, Never>] = [:]

    static let selectionDeadline: Duration = .milliseconds(600)

    var onAccessibilityRequired: (() -> Void)?

    var levelMeter: VoiceLevelMeter { recorder.levelMeter }
    var targetStack: StackItemFacts? {
        guard let store else { return nil }
        let id = state.session?.destinationStackID ?? store.selectedStackID
        return StackUIFacts(store: store).stack(id: id)
    }
    var destinationStacks: [StackItemFacts] {
        guard let store else { return [] }
        return StackUIFacts(store: store).stacks
    }

    func chooseDestination(_ id: UUID, context: NoteCaptureContext) {
        guard state.session?.context == context,
              destinationStacks.contains(where: { $0.id == id }) else { return }
        send(.chooseDestination(context, id))
    }

    var isOpen: Bool { state.session != nil }
    var captured: CapturedSelection? { state.session?.target?.captured }
    var note: String {
        get {
            switch state.session?.phase {
            case let .editing(note): return note
            case let .saving(request), let .saveFailed(request, _, _): return request.note.body
            default: return ""
            }
        }
        set { send(.changeNote(newValue)) }
    }
    var isNoteFrozen: Bool {
        guard let session = state.session, case .editing = session.phase else { return true }
        return session.saveAwaitsSelection
    }

    init(settings: AppSettings, voiceSettings: VoiceSettings, permissionState: PermissionState,
         selection: SelectionCapture, recorder: VoiceRecorder,
         frontApp: @escaping @MainActor () -> DictationTarget? = { CaptureController.frontmostApp() },
         surfaces: @escaping (CaptureController) -> CaptureSurfaces) {
        self.settings = settings
        self.voiceSettings = voiceSettings
        self.permissionState = permissionState
        self.selection = selection
        self.recorder = recorder
        self.frontApp = frontApp
        self.makeSurfaces = surfaces
        recorder.observe { [weak self] in self?.receive($0) }
    }

    private func receive(_ output: VoiceOutput) {
        guard let context = state.session?.context else { return }
        switch output {
        case .started(context.noteID): send(.recordingStarted(context))
        case .partial(context.noteID, let text): send(.voicePartial(context, text))
        case .transcript(context.noteID, let text): send(.transcript(context, text))
        case .failed(context.noteID, let message): send(.failed(context, message))
        default: break
        }
    }

    static func frontmostApp() -> DictationTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return DictationTarget(processIdentifier: app.processIdentifier, appName: app.localizedName)
    }

    func configure(store: StackStore) {
        guard !state.isTornDown else { return }
        precondition(self.store == nil || self.store === store)
        self.store = store
    }

    func warmUp() {
        guard !state.isTornDown else { return }
        recorder.chooseMicrophone(voiceSettings.inputDeviceUID)
        recorder.warmUp()
        surfaces.prepare()
    }

    func setVoiceMode(_ mode: VoiceRecordingMode) {
        voiceSettings.send(.voiceMode(mode))
        send(.voiceModeChanged(mode))
    }

    var transcriptionPreview: Bool { voiceSettings.transcriptionPreview }
    var transcriptionPreviewLines: Int { voiceSettings.transcriptionPreviewLines }
    var transcriptionPreviewFontSize: Int { voiceSettings.transcriptionPreviewFontSize }
    var transcriptionPreviewOpacity: Int { voiceSettings.transcriptionPreviewOpacity }

    func setTranscriptionPreview(_ on: Bool) {
        voiceSettings.send(.transcriptionPreview(on))
    }

    func stepTranscriptionPreviewLines(bySteps steps: Int) {
        voiceSettings.send(.transcriptionPreviewLines(transcriptionPreviewLines + steps))
    }

    func stepTranscriptionPreviewFontSize(bySteps steps: Int) {
        voiceSettings.send(.transcriptionPreviewFontSize(transcriptionPreviewFontSize + steps))
    }

    func stepTranscriptionPreviewOpacity(bySteps steps: Int) {
        voiceSettings.send(.transcriptionPreviewOpacity(
            transcriptionPreviewOpacity + steps * VoiceSettings.previewOpacityStep
        ))
    }

    func chooseMicrophone(uid: String?, devices: [AudioInputDevice]) {
        let name = uid.flatMap { id in devices.first { $0.uid == id }?.name }
        voiceSettings.send(.inputDevice(uid: uid, name: name))
        recorder.chooseMicrophone(uid)
    }

    func beginCapture() {
        if let context = beginContext() { send(.begin(.text, context)) }
    }

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
        return NoteCaptureContext(stackID: store.selectedStackID)
    }

    func send(_ action: CaptureAction) {
        pending.append(action)
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            for effect in state.update(pending.removeFirst()) { run(effect) }
        }
        isDraining = false
    }

    private func run(_ effect: CaptureEffect) {
        switch effect {
        case .beginVoice:
            if let context = beginContext() { send(.begin(.voice, context)) } else { send(.voiceRefused) }
        case .beginDictation:
            guard let target = frontApp() else {
                NSSound.beep()
                send(.voiceRefused)
                return
            }
            if let context = beginContext() { send(.begin(.dictation, context, target)) } else { send(.voiceRefused) }
        case let .readSelection(context, mode):
            launch(.selection, context: context) { [selection, weak self] in
                .selection(context, try await selection.read(mode == .text ? .patient : .brief) {
                    self?.send(.selectionPending(context))
                })
            }
        case let .selectionDeadline(context):
            launch(.selectionDeadline, context: context) { [weak self] in
                try await Task.sleep(for: Self.selectionDeadline)
                self?.tasks.removeValue(forKey: .selection)?.cancel()
                return .selection(context, CapturedSelection(text: "", screenRect: nil))
            }
        case let .startRecording(context): recorder.start(context.noteID)
        case let .transcribe(context): recorder.stop(context.noteID)
        case let .insert(context, text, target):
            launch(.insertion, context: context) { [selection] in
                .inserted(context, try await selection.insertText(text, target.processIdentifier))
            }
        case let .commit(request):
            guard let store else { return }
            store.mutate(.addNote(stackID: request.destinationStackID, note: request.note)) {
                [weak self] outcome in
                guard let self, !self.state.isTornDown else { return }
                self.send(.saved(request, outcome))
            }
        case let .switchStack(id): store?.mutate(.switchStack(stackID: id))
        case .retry: store?.retryPendingMutations()
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
        store = nil
        onAccessibilityRequired = nil
    }
}
