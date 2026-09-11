import Foundation
import SendpointDomain

/// A preference, not a gesture inferred from how long the keys stay down.
nonisolated enum VoiceRecordingMode: String, CaseIterable, Sendable {
    case hold
    case tap

    var title: String { self == .hold ? "Hold" : "Tap" }
    var detail: String {
        switch self {
        case .hold: "Hold to speak, release to save."
        case .tap: "Press to speak, press again to save."
        }
    }
}

nonisolated struct CaptureSaveRequest: Equatable {
    let target: NoteCaptureTarget
    let destinationStackID: UUID
    let note: Note
}

nonisolated enum CaptureMode: Equatable { case text, voice }

nonisolated enum CapturePhase: Equatable {
    case selectingText
    case selectingVoice(recording: Bool, finishRequested: Bool)
    case startingVoice
    case recording
    case transcribing
    case editing(String)
    case saving(CaptureSaveRequest)
    case saveFailed(CaptureSaveRequest, message: String, retryable: Bool, targetMissing: Bool)
    case failed(String)
}

nonisolated struct CaptureSession: Equatable {
    let context: NoteCaptureContext
    let mode: CaptureMode
    var target: NoteCaptureTarget?
    var phase: CapturePhase
    /// ⌘↩ arrived while the selection was still being read; the save runs
    /// the moment the target exists.
    var saveAwaitsSelection = false
}

/// The physical state of the voice key, kept across captures so a key
/// repeat, an early failure, or Escape cannot start a second recording.
nonisolated struct VoiceGesture: Equatable {
    var mode: VoiceRecordingMode = .hold
    var keyHeld = false
    /// The current press has done its work; nothing happens until the key comes up.
    var releasePending = false
}

nonisolated enum CaptureAction {
    case begin(CaptureMode, NoteCaptureContext)
    /// The controller could not start a voice capture the reducer asked for.
    case voiceRefused
    case voicePressed
    case voiceReleased
    /// The status menu item: one press starts, the next finishes.
    case voiceToggled
    case voiceEscape
    case voiceModeChanged(VoiceRecordingMode)
    /// The selection reader has done everything that must happen before the
    /// note box takes over the keyboard; the rest may finish behind it.
    case selectionPending(NoteCaptureContext)
    case selection(NoteCaptureContext, CapturedSelection)
    case recordingStarted(NoteCaptureContext)
    case failed(NoteCaptureContext, String)
    case transcript(NoteCaptureContext, String)
    case changeNote(String)
    case save
    case finishVoice
    case cancelVoice
    case dismiss
    case retry
    case retarget(UUID)
    case prepared(CaptureSaveRequest, Note)
    case saved(CaptureSaveRequest, StackMutationOutcome, destinationExists: Bool)
    case failureTimeout(NoteCaptureContext)
    case teardown
}

nonisolated enum CaptureSurface { case editor, voice }

nonisolated enum CaptureEffect: Equatable {
    /// Check the store and permissions, then send `.begin(.voice, _)` or `.voiceRefused`.
    case beginVoice
    case readSelection(NoteCaptureContext, CaptureMode)
    case startRecording(NoteCaptureContext)
    case transcribe(NoteCaptureContext)
    case probe(NoteCaptureTarget)
    case save(CaptureSaveRequest)
    case commit(CaptureSaveRequest)
    case retry
    case abandon(NoteCaptureTarget)
    case show(CaptureSurface)
    case focusEditor
    case failureTimer(NoteCaptureContext)
    case close
    case beep
}

/// Pure workflow rules. Effects run only after the returned state is installed.
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
        case let .begin(mode, context):
            return begin(mode, context)
        case .voicePressed:
            guard !voice.keyHeld, !voice.releasePending else { return [] }
            voice.keyHeld = true
            guard let session else { return [.beginVoice] }
            voice.releasePending = true
            return session.mode == .voice ? finishOrBeep(session) : busy(session)
        case .voiceRefused:
            guard voice.keyHeld else { return [] }
            voice.keyHeld = false
            voice.releasePending = true
            return []
        case .voiceReleased:
            let wasHeld = voice.keyHeld
            voice.keyHeld = false
            if voice.releasePending {
                voice.releasePending = false
                return []
            }
            guard wasHeld, voice.mode == .hold, session?.mode == .voice else { return [] }
            return update(.finishVoice)
        case .voiceToggled:
            guard !voice.keyHeld, !voice.releasePending else { return [] }
            guard let session else { return [.beginVoice] }
            return session.mode == .voice ? finishOrBeep(session) : busy(session)
        case .voiceEscape:
            guard session?.mode == .voice else { return [] }
            if voice.keyHeld {
                voice.keyHeld = false
                voice.releasePending = true
            }
            return update(.cancelVoice)
        case let .voiceModeChanged(mode):
            voice = VoiceGesture(mode: mode)
            return session?.mode == .voice ? update(.cancelVoice) : []
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
                effects = [.probe(target), .show(.editor)]
            case let .editing(note) where session.target == nil:
                // The box opened early; the passage catches up with it.
                effects = [.probe(target)]
                if session.saveAwaitsSelection {
                    session.saveAwaitsSelection = false
                    if let note = target.note(body: note) {
                        let request = CaptureSaveRequest(target: target,
                            destinationStackID: target.stackID, note: note)
                        session.phase = .saving(request)
                        effects.append(.save(request))
                    } else {
                        effects.append(.beep)
                    }
                }
            case let .selectingVoice(recording, finishRequested):
                session.phase = recording ? (finishRequested ? .transcribing : .recording) : .startingVoice
                effects = [.probe(target)]
                if finishRequested && recording { effects.append(.transcribe(context)) }
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
            guard let target = session.target,
                  let note = target.note(body: note)
            else {
                if session.phase == .transcribing {
                    session.phase = .failed("No speech was found.")
                    lifecycle = .active(session)
                    return [.failureTimer(session.context)]
                }
                if session.target == nil, note.nonblank != nil {
                    // The passage is still on its way; save as soon as it lands.
                    session.saveAwaitsSelection = true
                    lifecycle = .active(session)
                    return []
                }
                return [.beep]
            }
            let request = CaptureSaveRequest(target: target,
                destinationStackID: target.stackID, note: note)
            session.phase = .saving(request)
            effects = [.save(request)]
        case let .failed(context, message):
            guard context == session.context else { return [] }
            switch session.phase {
            case .selectingVoice, .startingVoice, .recording, .transcribing:
                session.phase = .failed(message)
                effects = [.failureTimer(context)]
            case .selectingText:
                // A typed note never waits on the passage: open without one.
                return update(.selection(context, CapturedSelection(text: "")))
            case .editing where session.target == nil:
                return update(.selection(context, CapturedSelection(text: "")))
            default: return []
            }
        case let .prepared(request, note):
            guard session.phase == .saving(request), note.id == request.note.id,
                  note.provenance.application == request.target.application else { return [] }
            let prepared = CaptureSaveRequest(target: request.target,
                destinationStackID: request.destinationStackID, note: note)
            session.phase = .saving(prepared)
            effects = [.commit(prepared)]
        case let .saved(request, outcome, destinationExists):
            let current: CaptureSaveRequest
            switch session.phase {
            case let .saving(value), let .saveFailed(value, _, _, _): current = value
            default: return []
            }
            guard current == request, request.target.context == session.context else { return [] }
            switch outcome {
            case .committed: return finish(session, abandon: false)
            case let .commitFailed(message):
                session.phase = .saveFailed(request, message: "Couldn’t save the note: \(message)",
                    retryable: true, targetMissing: false)
            case let .rejected(message):
                session.phase = .saveFailed(request,
                    message: destinationExists ? message : "That stack was deleted.",
                    retryable: false, targetMissing: !destinationExists)
            case .cancelled, .noOp:
                session.phase = .saveFailed(request, message: "The note wasn’t saved.",
                    retryable: false, targetMissing: false)
            }
            effects = [.show(.editor)]
        case .retry:
            guard case let .saveFailed(request, _, true, _) = session.phase else { return [] }
            session.phase = .saving(request)
            effects = [.retry]
        case let .retarget(destination):
            guard case let .saveFailed(old, _, false, true) = session.phase else { return [] }
            let request = CaptureSaveRequest(target: old.target, destinationStackID: destination,
                note: old.note)
            session.phase = .saving(request)
            effects = [.abandon(old.target), .save(request)]
        case .dismiss:
            switch session.phase {
            case .saving, .saveFailed(_, _, true, _): return finish(session, abandon: false)
            default: return finish(session)
            }
        case let .failureTimeout(context):
            guard context == session.context, case .failed = session.phase else { return [] }
            return finish(session)
        case .begin, .teardown, .voiceRefused, .voicePressed, .voiceReleased, .voiceToggled,
             .voiceEscape, .voiceModeChanged:
            return []
        }
        lifecycle = .active(session)
        return effects
    }

    private mutating func begin(_ mode: CaptureMode, _ context: NoteCaptureContext) -> [CaptureEffect] {
        guard let session else {
            lifecycle = .active(CaptureSession(context: context, mode: mode, phase: mode == .text
                ? .selectingText : .selectingVoice(recording: false, finishRequested: false)))
            return mode == .text ? [.readSelection(context, mode)]
                : [.show(.voice), .startRecording(context), .readSelection(context, mode)]
        }
        return busy(session)
    }

    /// A capture is already open; point the user at it.
    private func busy(_ session: CaptureSession) -> [CaptureEffect] {
        if case .editing = session.phase { return [.focusEditor] }
        return [.beep]
    }

    /// The voice key was pressed while its own capture is up: finish while it
    /// is still listening, otherwise there is nothing more to finish.
    private mutating func finishOrBeep(_ session: CaptureSession) -> [CaptureEffect] {
        switch session.phase {
        case .selectingVoice, .startingVoice, .recording: return update(.finishVoice)
        default: return [.beep]
        }
    }

    private mutating func finish(_ session: CaptureSession, abandon: Bool = true) -> [CaptureEffect] {
        lifecycle = .idle
        // The key is still down after its capture ended; its release must not start another.
        if session.mode == .voice, voice.keyHeld {
            voice.keyHeld = false
            voice.releasePending = true
        }
        return (abandon ? session.target.map { [CaptureEffect.abandon($0)] } ?? [] : []) + [.close]
    }
}
