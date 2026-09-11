import Foundation
import SendpointDomain

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

nonisolated enum CaptureAction {
    case begin(CaptureMode, NoteCaptureContext)
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
nonisolated enum CaptureState: Equatable {
    case idle
    case active(CaptureSession)
    case tornDown

    var session: CaptureSession? {
        if case let .active(session) = self { return session }
        return nil
    }

    mutating func update(_ action: CaptureAction) -> [CaptureEffect] {
        guard self != .tornDown else { return [] }
        if case .teardown = action {
            self = .tornDown
            return [.close]
        }
        if case let .begin(mode, context) = action {
            guard self == .idle else {
                if case .editing = session?.phase { return [.focusEditor] }
                return [.beep]
            }
            self = .active(CaptureSession(context: context, mode: mode, phase: mode == .text
                ? .selectingText : .selectingVoice(recording: false, finishRequested: false)))
            return mode == .text ? [.readSelection(context, mode)]
                : [.show(.voice), .startRecording(context), .readSelection(context, mode)]
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
                    self = .active(session)
                    return [.failureTimer(session.context)]
                }
                if session.target == nil, note.nonblank != nil {
                    // The passage is still on its way; save as soon as it lands.
                    session.saveAwaitsSelection = true
                    self = .active(session)
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
        case .begin, .teardown: return []
        }
        self = .active(session)
        return effects
    }

    private mutating func finish(_ session: CaptureSession, abandon: Bool = true) -> [CaptureEffect] {
        self = .idle
        return (abandon ? session.target.map { [CaptureEffect.abandon($0)] } ?? [] : []) + [.close]
    }
}
