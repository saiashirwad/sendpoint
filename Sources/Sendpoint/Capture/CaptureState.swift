import Foundation
import SendpointDomain

nonisolated enum VoiceRecordingMode: String, CaseIterable, Sendable {
    case hold
    case tap

    var title: String { self == .hold ? "Hold" : "Tap" }
    var detail: String {
        switch self {
        case .hold: "Hold to speak, release to finish."
        case .tap: "Press to speak, press again to finish."
        }
    }
}

nonisolated enum SpeechKey: Equatable, Sendable {
    case note, dictate

    var mode: CaptureMode { self == .note ? .voice : .dictation }
}

nonisolated struct DictationTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let appName: String?
}

nonisolated struct CaptureSaveRequest: Equatable {
    let target: NoteCaptureTarget
    let destinationStackID: UUID
    let note: Note
}

nonisolated enum CaptureMode: Equatable, Sendable { case text, voice, dictation }

nonisolated enum CapturePhase: Equatable {
    case selectingText
    case selectingVoice(recording: Bool, finishRequested: Bool)
    case startingVoice
    case recording
    case transcribing
    case inserting
    case editing(String)
    case saving(CaptureSaveRequest)
    case saveFailed(CaptureSaveRequest, message: String, retryable: Bool)
    case failed(String)
}

nonisolated enum CaptureDestinationPicker: Equatable { case closed, open }

nonisolated struct CaptureSession: Equatable {
    let context: NoteCaptureContext
    let mode: CaptureMode
    var target: NoteCaptureTarget?
    var phase: CapturePhase
    var liveTranscript: String? = nil
    var destinationStackID: UUID
    var destinationPicker: CaptureDestinationPicker = .closed
    var saveAwaitsSelection = false
    var dictationTarget: DictationTarget? = nil

    var canChooseDestination: Bool {
        guard !saveAwaitsSelection, mode != .dictation else { return false }
        switch phase {
        case .selectingText, .startingVoice, .recording, .editing,
             .selectingVoice(_, finishRequested: false): return true
        default: return false
        }
    }
}

nonisolated struct VoiceGesture: Equatable {
    var mode: VoiceRecordingMode = .hold
    var keyHeld = false
    var releasePending = false
    var key: SpeechKey? = nil
}

nonisolated enum CaptureAction {
    case begin(CaptureMode, NoteCaptureContext, DictationTarget? = nil)
    case voiceRefused
    case voicePressed
    case voiceReleased
    case voiceToggled
    case dictatePressed
    case dictateReleased
    case dictateToggled
    case voiceEscape
    case voiceModeChanged(VoiceRecordingMode)
    case selectionPending(NoteCaptureContext)
    case selection(NoteCaptureContext, CapturedSelection)
    case recordingStarted(NoteCaptureContext)
    case failed(NoteCaptureContext, String)
    case transcript(NoteCaptureContext, String)
    case voicePartial(NoteCaptureContext, String)
    case changeNote(String)
    case toggleDestinations(NoteCaptureContext)
    case dismissDestinations(NoteCaptureContext)
    case chooseDestination(NoteCaptureContext, UUID)
    case stackSelected(UUID)
    case save
    case finishVoice
    case cancelVoice
    case dismiss
    case retry
    case saved(CaptureSaveRequest, StackMutationOutcome)
    case inserted(NoteCaptureContext, Bool)
    case failureTimeout(NoteCaptureContext)
    case teardown
}

nonisolated enum CaptureSurface { case editor, voice }

nonisolated enum CaptureEffect: Equatable {
    case beginVoice
    case beginDictation
    case readSelection(NoteCaptureContext, CaptureMode)
    case startRecording(NoteCaptureContext)
    case transcribe(NoteCaptureContext)
    case insert(NoteCaptureContext, String, DictationTarget)
    case commit(CaptureSaveRequest)
    case switchStack(UUID)
    case retry
    case show(CaptureSurface)
    case focusEditor
    case failureTimer(NoteCaptureContext)
    case close
    case beep
}

nonisolated struct CaptureState: Equatable {
    enum Lifecycle: Equatable {
        case idle
        case active(CaptureSession)
        case tornDown
    }

    var lifecycle: Lifecycle = .idle
    var voice = VoiceGesture()

    var session: CaptureSession? {
        if case let .active(session) = lifecycle { return session }
        return nil
    }

    var isTornDown: Bool { lifecycle == .tornDown }

    mutating func update(_ action: CaptureAction) -> [CaptureEffect] {
        guard lifecycle != .tornDown else { return [] }
        switch action {
        case .teardown:
            lifecycle = .tornDown
            return [.close]
        case let .begin(mode, context, target):
            return begin(mode, context, target: target)
        case .voicePressed: return pressed(.note)
        case .dictatePressed: return pressed(.dictate)
        case .voiceRefused:
            guard voice.keyHeld else { return [] }
            voice.keyHeld = false
            voice.releasePending = true
            return []
        case .voiceReleased: return released(.note)
        case .dictateReleased: return released(.dictate)
        case .voiceToggled: return toggled(.note)
        case .dictateToggled: return toggled(.dictate)
        case .voiceEscape:
            guard let session, session.mode != .text else { return [] }
            if session.destinationPicker == .open {
                return update(.dismissDestinations(session.context))
            }
            if voice.keyHeld {
                voice.keyHeld = false
                voice.releasePending = true
            }
            return update(.cancelVoice)
        case let .voiceModeChanged(mode):
            voice = VoiceGesture(mode: mode)
            return session.map { $0.mode != .text } == true ? update(.cancelVoice) : []
        default:
            break
        }

        guard var session else { return [] }
        var effects: [CaptureEffect] = []
        switch action {
        case let .selectionPending(context):
            guard context == session.context, session.phase == .selectingText else { return [] }
            session.phase = .editing("")
            effects = [.show(.editor)]
        case let .selection(context, selection):
            guard context == session.context else { return [] }
            let target = context.target(captured: selection)
            switch session.phase {
            case .selectingText:
                session.phase = .editing("")
                effects = [.show(.editor)]
            case let .editing(note) where session.target == nil:
                if session.saveAwaitsSelection {
                    session.saveAwaitsSelection = false
                    if let note = target.note(body: note) {
                        let request = CaptureSaveRequest(target: target,
                            destinationStackID: session.destinationStackID, note: note)
                        session.phase = .saving(request)
                        effects.append(.commit(request))
                    } else {
                        effects = [.beep]
                    }
                }
            case let .selectingVoice(recording, finishRequested):
                session.phase = recording ? (finishRequested ? .transcribing : .recording) : .startingVoice
                effects = finishRequested && recording ? [.transcribe(context)] : []
            default: return []
            }
            session.target = target
        case let .recordingStarted(context):
            guard context == session.context else { return [] }
            switch session.phase {
            case let .selectingVoice(_, finish):
                session.phase = .selectingVoice(recording: true, finishRequested: finish)
            case .startingVoice: session.phase = .recording
            default: return []
            }
        case .finishVoice:
            switch session.phase {
            case .selectingVoice(recording: true, _):
                session.phase = .selectingVoice(recording: true, finishRequested: true)
            case .selectingVoice, .startingVoice: return finish(session)
            case .recording:
                session.phase = .transcribing
                effects = [.transcribe(session.context)]
            default: return []
            }
        case .cancelVoice:
            switch session.phase {
            case .selectingVoice, .startingVoice, .recording, .failed: return finish(session)
            default: return []
            }
        case let .changeNote(note):
            guard case .editing = session.phase, !session.saveAwaitsSelection else { return [] }
            session.phase = .editing(note)
        case let .toggleDestinations(context):
            guard context == session.context, session.canChooseDestination else { return [] }
            session.destinationPicker = session.destinationPicker == .open ? .closed : .open
        case let .dismissDestinations(context):
            guard context == session.context else { return [] }
            session.destinationPicker = .closed
        case let .chooseDestination(context, destination):
            guard context == session.context, session.canChooseDestination,
                  session.destinationPicker == .open else { return [] }
            session.destinationStackID = destination
            session.destinationPicker = .closed
            effects = [.switchStack(destination)]
        case let .stackSelected(destination):
            guard session.canChooseDestination else { return [] }
            session.destinationStackID = destination
            session.destinationPicker = .closed
        case .save, .transcript:
            let note: String
            switch action {
            case let .transcript(context, text):
                guard context == session.context, session.phase == .transcribing else { return [] }
                note = text
            default:
                guard case let .editing(text) = session.phase else { return [] }
                note = text
            }
            if session.mode == .dictation {
                guard let target = session.dictationTarget, let text = note.nonblank else {
                    session.phase = .failed(note.nonblank == nil ? "No speech was found." : "Couldn’t paste.")
                    lifecycle = .active(session)
                    return [.failureTimer(session.context)]
                }
                session.phase = .inserting
                lifecycle = .active(session)
                return [.insert(session.context, text, target)]
            }
            guard let target = session.target,
                  let note = target.note(body: note)
            else {
                if session.phase == .transcribing {
                    session.phase = .failed("No speech was found.")
                    lifecycle = .active(session)
                    return [.failureTimer(session.context)]
                }
                if session.target == nil, note.nonblank != nil {
                    session.saveAwaitsSelection = true
                    session.destinationPicker = .closed
                    lifecycle = .active(session)
                    return []
                }
                return [.beep]
            }
            let request = CaptureSaveRequest(target: target,
                destinationStackID: session.destinationStackID, note: note)
            session.phase = .saving(request)
            effects = [.commit(request)]
        case let .voicePartial(context, text):
            guard context == session.context else { return [] }
            switch session.phase {
            case .recording, .selectingVoice(recording: true, _), .transcribing:
                session.liveTranscript = text.nonblank
            default: return []
            }
        case let .failed(context, message):
            guard context == session.context else { return [] }
            session.liveTranscript = nil
            switch session.phase {
            case .selectingVoice, .startingVoice, .recording, .transcribing, .inserting:
                session.phase = .failed(message)
                effects = [.failureTimer(context)]
            case .selectingText:
                return update(.selection(context, CapturedSelection(text: "")))
            case .editing where session.target == nil:
                return update(.selection(context, CapturedSelection(text: "")))
            default: return []
            }
        case let .saved(request, outcome):
            let current: CaptureSaveRequest
            switch session.phase {
            case let .saving(value), let .saveFailed(value, _, _): current = value
            default: return []
            }
            guard current == request, request.target.context == session.context else { return [] }
            switch outcome {
            case .committed: return finish(session)
            case let .commitFailed(message):
                session.phase = .saveFailed(request, message: "Couldn’t save the note: \(message)",
                    retryable: true)
            case let .rejected(message):
                session.phase = .saveFailed(request, message: message, retryable: false)
            case .cancelled, .noOp:
                session.phase = .saveFailed(request, message: "The note wasn’t saved.", retryable: false)
            }
            effects = [.show(.editor)]
        case .retry:
            guard case let .saveFailed(request, _, true) = session.phase else { return [] }
            session.phase = .saving(request)
            effects = [.retry]
        case let .inserted(context, pasted):
            guard context == session.context, session.phase == .inserting else { return [] }
            if pasted { return finish(session) }
            session.phase = .failed("Couldn’t paste.")
            effects = [.failureTimer(context)]
        case .dismiss:
            return finish(session)
        case let .failureTimeout(context):
            guard context == session.context, case .failed = session.phase else { return [] }
            return finish(session)
        case .begin, .teardown, .voiceRefused, .voicePressed, .voiceReleased, .voiceToggled,
             .dictatePressed, .dictateReleased, .dictateToggled, .voiceEscape, .voiceModeChanged:
            return []
        }
        if !session.canChooseDestination { session.destinationPicker = .closed }
        lifecycle = .active(session)
        return effects
    }

    private mutating func begin(
        _ mode: CaptureMode, _ context: NoteCaptureContext, target: DictationTarget?
    ) -> [CaptureEffect] {
        guard let session else {
            let phase: CapturePhase = switch mode {
            case .text: .selectingText
            case .voice: .selectingVoice(recording: false, finishRequested: false)
            case .dictation: .startingVoice
            }
            lifecycle = .active(CaptureSession(context: context, mode: mode, phase: phase,
                destinationStackID: context.stackID, dictationTarget: mode == .dictation ? target : nil))
            switch mode {
            case .text: return [.readSelection(context, mode)]
            case .voice: return [.show(.voice), .startRecording(context), .readSelection(context, mode)]
            case .dictation: return [.show(.voice), .startRecording(context)]
            }
        }
        return busy(session)
    }

    private mutating func pressed(_ key: SpeechKey) -> [CaptureEffect] {
        guard !voice.keyHeld, !voice.releasePending else { return [] }
        voice.keyHeld = true
        voice.key = key
        guard let session else { return [key == .note ? .beginVoice : .beginDictation] }
        voice.releasePending = true
        return session.mode == key.mode ? finishOrBeep(session) : busy(session)
    }

    private mutating func released(_ key: SpeechKey) -> [CaptureEffect] {
        guard voice.key == key else { return [] }
        let wasHeld = voice.keyHeld
        voice.keyHeld = false
        voice.key = nil
        if voice.releasePending {
            voice.releasePending = false
            return []
        }
        guard wasHeld, voice.mode == .hold, session?.mode == key.mode else { return [] }
        return update(.finishVoice)
    }

    private mutating func toggled(_ key: SpeechKey) -> [CaptureEffect] {
        guard !voice.keyHeld, !voice.releasePending else { return [] }
        guard let session else { return [key == .note ? .beginVoice : .beginDictation] }
        return session.mode == key.mode ? finishOrBeep(session) : busy(session)
    }

    private func busy(_ session: CaptureSession) -> [CaptureEffect] {
        if case .editing = session.phase { return [.focusEditor] }
        return [.beep]
    }

    private mutating func finishOrBeep(_ session: CaptureSession) -> [CaptureEffect] {
        switch session.phase {
        case .selectingVoice, .startingVoice, .recording: return update(.finishVoice)
        default: return [.beep]
        }
    }

    private mutating func finish(_ session: CaptureSession) -> [CaptureEffect] {
        lifecycle = .idle
        if session.mode != .text, voice.keyHeld {
            voice.keyHeld = false
            voice.releasePending = true
        }
        return [.close]
    }
}
