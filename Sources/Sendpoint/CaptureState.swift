import Foundation
import SendpointDomain

struct CaptureSaveRequest: Equatable {
    let target: AnnotationCaptureTarget
    let destinationSessionID: UUID
    let annotation: Annotation
}

enum CaptureMode: Equatable { case text, voice }

enum CapturePhase: Equatable {
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

struct CaptureSession: Equatable {
    let context: AnnotationCaptureContext
    let mode: CaptureMode
    var target: AnnotationCaptureTarget?
    var phase: CapturePhase
}

enum CaptureAction {
    case begin(CaptureMode, AnnotationCaptureContext)
    case selection(AnnotationCaptureContext, CapturedSelection)
    case recordingStarted(AnnotationCaptureContext)
    case failed(AnnotationCaptureContext, String)
    case transcript(AnnotationCaptureContext, String)
    case changeNote(String)
    case save
    case finishVoice
    case cancelVoice
    case dismiss
    case retry
    case retarget(UUID)
    case prepared(CaptureSaveRequest, Annotation)
    case saved(CaptureSaveRequest, AnnotationStoreMutationOutcome, destinationExists: Bool)
    case failureTimeout(AnnotationCaptureContext)
    case teardown
}

enum CaptureSurface { case editor, voice }

enum CaptureEffect: Equatable {
    case readSelection(AnnotationCaptureContext, CaptureMode)
    case startRecording(AnnotationCaptureContext)
    case transcribe(AnnotationCaptureContext)
    case probe(AnnotationCaptureTarget)
    case save(CaptureSaveRequest)
    case commit(CaptureSaveRequest)
    case retry
    case abandon(AnnotationCaptureTarget)
    case show(CaptureSurface)
    case focusEditor
    case failureTimer(AnnotationCaptureContext)
    case close
    case beep
}

/// Pure workflow rules. Effects run only after the returned state is installed.
enum CaptureState: Equatable {
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
        case let .selection(context, selection):
            guard context == session.context else { return [] }
            let target = context.target(captured: selection)
            switch session.phase {
            case .selectingText:
                session.phase = .editing("")
                effects = [.probe(target), .show(.editor)]
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
            guard case .editing = session.phase else { return [] }
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
                  let annotation = target.annotation(note: note)
            else {
                if session.phase == .transcribing {
                    session.phase = .failed("No speech was found.")
                    self = .active(session)
                    return [.failureTimer(session.context)]
                }
                return [.beep]
            }
            let request = CaptureSaveRequest(target: target,
                destinationSessionID: target.sessionID, annotation: annotation)
            session.phase = .saving(request)
            effects = [.save(request)]
        case let .failed(context, message):
            guard context == session.context else { return [] }
            switch session.phase {
            case .selectingVoice, .startingVoice, .recording, .transcribing:
                session.phase = .failed(message)
                effects = [.failureTimer(context)]
            default: return []
            }
        case let .prepared(request, annotation):
            guard session.phase == .saving(request), annotation.id == request.annotation.id,
                  annotation.provenance.application == request.target.application else { return [] }
            let prepared = CaptureSaveRequest(target: request.target,
                destinationSessionID: request.destinationSessionID, annotation: annotation)
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
            let request = CaptureSaveRequest(target: old.target, destinationSessionID: destination,
                annotation: old.annotation)
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
