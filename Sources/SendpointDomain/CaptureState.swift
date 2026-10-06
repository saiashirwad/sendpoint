import CoreGraphics
import Foundation

public nonisolated struct CapturedSelection: Equatable, Sendable {
    public var text: String
    public var screenRect: CGRect?

    public init(text: String, screenRect: CGRect? = nil) {
        self.text = text
        self.screenRect = screenRect
    }
}

public nonisolated enum VoiceRecordingMode: String, CaseIterable, Sendable {
    case hold, tap
    public var title: String { self == .hold ? "Hold" : "Tap" }
    public var detail: String {
        switch self {
        case .hold: "Hold to speak, release to finish."
        case .tap: "Press to speak, press again to finish."
        }
    }
}

public nonisolated enum SpeechKey: Equatable, Sendable { case note, dictate }

public nonisolated struct DictationTarget: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let appName: String?
    public init(processIdentifier: pid_t, appName: String?) {
        self.processIdentifier = processIdentifier
        self.appName = appName
    }
}

public nonisolated struct CaptureIdentity: Equatable {
    public let sourceStack: StackSlot
    public let noteID: UUID
    public let createdAt: Date
    public init(sourceStack: StackSlot, noteID: UUID = UUID(), createdAt: Date = Date()) {
        self.sourceStack = sourceStack
        self.noteID = noteID
        self.createdAt = createdAt
    }
}

public nonisolated enum CaptureStart: Equatable {
    case typed(CaptureIdentity)
    case voice(CaptureIdentity)
    case dictation(CaptureIdentity, DictationTarget)

    public var identity: CaptureIdentity {
        switch self {
        case let .typed(id), let .voice(id), let .dictation(id, _): id
        }
    }
}

public nonisolated enum SelectionProgress: Equatable {
    case pending
    case resolved(CapturedSelection)
    public var captured: CapturedSelection? {
        if case let .resolved(value) = self { return value }
        return nil
    }
}

public nonisolated enum DestinationChoice: Equatable {
    case closed(StackSlot)
    case picking(StackSlot)
    public var slot: StackSlot {
        switch self { case let .closed(slot), let .picking(slot): slot }
    }
    public var isPickerOpen: Bool {
        if case .picking = self { return true }
        return false
    }
}

public nonisolated struct EditableDraft: Equatable {
    public var body: String
    public var destination: DestinationChoice
}

public nonisolated struct FrozenTypedDraft: Equatable {
    public let body: String
    public let destination: StackSlot
}

public nonisolated enum SpeechDestination: Equatable {
    case note(SelectionProgress, DestinationChoice)
    case dictation(DictationTarget)
}

public nonisolated enum ResolvedSpeechDestination: Equatable {
    case note(CapturedSelection, StackSlot)
    case dictation(DictationTarget)
}

public nonisolated enum RecordingProgress: Equatable {
    case starting
    case live(String?)
}

public nonisolated enum NoteInput: Equatable { case typed, voice }

public nonisolated struct CaptureSaveRequest: Equatable {
    public let identity: CaptureIdentity
    public let selection: CapturedSelection
    public let destinationStackID: StackSlot
    public let note: Note
    public let input: NoteInput

    public init(identity: CaptureIdentity, selection: CapturedSelection,
                destinationStackID: StackSlot, note: Note, input: NoteInput) {
        self.identity = identity
        self.selection = selection
        self.destinationStackID = destinationStackID
        self.note = note
        self.input = input
    }
}

public nonisolated enum SaveFailure: Equatable {
    case retryable(String)
    case terminal(String)
    public var message: String {
        switch self { case let .retryable(message), let .terminal(message): message }
    }
    public var canRetry: Bool {
        if case .retryable = self { return true }
        return false
    }
}

public nonisolated enum SpeechOrigin: Equatable {
    case note(SelectionProgress, StackSlot)
    case dictation(DictationTarget)
    var key: SpeechKey {
        switch self { case .note: .note; case .dictation: .dictate }
    }
}

public nonisolated enum CaptureWork: Equatable {
    case readingText(DestinationChoice)
    case editing(SelectionProgress, EditableDraft)
    case awaitingTextSelection(FrozenTypedDraft)
    case listening(SpeechDestination, RecordingProgress)
    case joiningVoice(StackSlot, String?)
    case transcribing(ResolvedSpeechDestination, String?)
    case saving(CaptureSaveRequest)
    case saveFailed(CaptureSaveRequest, SaveFailure)
    case inserting(DictationTarget, String)
    case speechFailed(SpeechOrigin, String)
}

public nonisolated enum CaptureEditor: Equatable {
    case editing(String)
    case saving(String)
    case failed(String, SaveFailure)
    public var body: String {
        switch self { case let .editing(body), let .saving(body), let .failed(body, _): body }
    }
    public var isEditable: Bool {
        if case .editing = self { return true }
        return false
    }
}

public nonisolated struct CaptureSpeech: Equatable {
    public enum Stage: Equatable { case starting, listening, transcribing, saving, inserting, failed(String) }
    public let origin: SpeechOrigin
    public let stage: Stage
    public let preview: String?
}

public nonisolated enum CaptureDestination: Equatable {
    case choosing(DestinationChoice)
    case frozen(StackSlot)
    public var slot: StackSlot {
        switch self { case let .choosing(choice): choice.slot; case let .frozen(slot): slot }
    }
    public var isPickerOpen: Bool {
        if case let .choosing(choice) = self { return choice.isPickerOpen }
        return false
    }
    public var canChoose: Bool {
        if case .choosing = self { return true }
        return false
    }
}

public nonisolated enum SpeechLatch: Equatable {
    case up
    case down(SpeechKey)
    case consumeRelease(SpeechKey)
}

public nonisolated enum CaptureEvent {
    case begin(CaptureStart)
    case voiceRefused, voicePressed, voiceReleased, voiceToggled
    case dictatePressed, dictateReleased, dictateToggled, voiceEscape
    case voiceModeChanged(VoiceRecordingMode)
    case selectionPending(CaptureIdentity)
    case selection(CaptureIdentity, CapturedSelection)
    case recordingStarted(CaptureIdentity)
    case failed(CaptureIdentity, String)
    case transcript(CaptureIdentity, String)
    case voicePartial(CaptureIdentity, String)
    case changeNote(String)
    case toggleDestinations(CaptureIdentity)
    case dismissDestinations(CaptureIdentity)
    case chooseDestination(CaptureIdentity, StackSlot)
    case stackSelected(StackSlot)
    case save, finishVoice, cancelVoice, dismiss, retry
    case saved(CaptureSaveRequest, StackMutationOutcome)
    case inserted(CaptureIdentity, Bool)
    case failureTimeout(CaptureIdentity)
    case teardown
}

public nonisolated enum CaptureSurface { case editor, voice }

public nonisolated enum CaptureEffect: Equatable {
    case beginVoice, beginDictation
    case readSelection(CaptureIdentity, CaptureSurface)
    case selectionDeadline(CaptureIdentity)
    case startRecording(CaptureIdentity)
    case transcribe(CaptureIdentity)
    case insert(CaptureIdentity, String, DictationTarget)
    case commit(CaptureSaveRequest)
    case switchStack(StackSlot)
    case retry
    case show(CaptureSurface)
    case focusEditor
    case failureTimer(CaptureIdentity)
    case close, beep
}

public nonisolated struct CaptureState: Equatable {
    public enum Lifecycle: Equatable {
        case idle
        case active(CaptureIdentity, CaptureWork)
        case tornDown
    }
    public private(set) var lifecycle: Lifecycle = .idle
    public private(set) var voiceMode: VoiceRecordingMode = .hold
    public private(set) var speechLatch: SpeechLatch = .up
    public init() {}

    public var identity: CaptureIdentity? {
        if case let .active(id, _) = lifecycle { return id }
        return nil
    }
    public var work: CaptureWork? {
        if case let .active(_, work) = lifecycle { return work }
        return nil
    }
    public var isTornDown: Bool { lifecycle == .tornDown }

    public var editor: CaptureEditor? {
        switch work {
        case let .editing(_, draft): .editing(draft.body)
        case let .awaitingTextSelection(draft): .saving(draft.body)
        case let .saving(request): .saving(request.note.body)
        case let .saveFailed(request, failure): .failed(request.note.body, failure)
        default: nil
        }
    }

    public var speech: CaptureSpeech? {
        switch work {
        case let .listening(destination, recording):
            let origin: SpeechOrigin = switch destination {
            case let .note(selection, choice): .note(selection, choice.slot)
            case let .dictation(target): .dictation(target)
            }
            switch recording {
            case .starting: return CaptureSpeech(origin: origin, stage: .starting, preview: nil)
            case let .live(preview): return CaptureSpeech(origin: origin, stage: .listening, preview: preview)
            }
        case let .joiningVoice(slot, preview):
            return CaptureSpeech(origin: .note(.pending, slot), stage: .listening, preview: preview)
        case let .transcribing(destination, preview):
            return CaptureSpeech(origin: destination.origin, stage: .transcribing, preview: preview)
        case let .saving(request) where request.input == .voice:
            return CaptureSpeech(origin: .note(.resolved(request.selection), request.destinationStackID),
                                 stage: .saving, preview: nil)
        case let .inserting(target, _):
            return CaptureSpeech(origin: .dictation(target), stage: .inserting, preview: nil)
        case let .speechFailed(origin, message):
            return CaptureSpeech(origin: origin, stage: .failed(message), preview: nil)
        default: return nil
        }
    }

    public var captured: CapturedSelection? {
        switch work {
        case let .editing(selection, _): selection.captured
        case let .listening(.note(selection, _), _): selection.captured
        case let .transcribing(.note(selection, _), _): selection
        case let .saving(request), let .saveFailed(request, _): request.selection
        case let .speechFailed(.note(selection, _), _): selection.captured
        default: nil
        }
    }

    public var destination: CaptureDestination? {
        switch work {
        case let .readingText(choice): .choosing(choice)
        case let .editing(_, draft): .choosing(draft.destination)
        case let .listening(.note(_, choice), _): .choosing(choice)
        case let .awaitingTextSelection(draft): .frozen(draft.destination)
        case let .joiningVoice(slot, _), let .transcribing(.note(_, slot), _),
             let .speechFailed(.note(_, slot), _): .frozen(slot)
        case let .saving(request), let .saveFailed(request, _): .frozen(request.destinationStackID)
        default: nil
        }
    }

    public mutating func update(_ event: CaptureEvent) -> [CaptureEffect] {
        guard !isTornDown else { return [] }
        switch event {
        case .teardown:
            lifecycle = .tornDown
            return [.close]
        case let .begin(start):
            guard identity == nil else { return busy() }
            let id = start.identity
            switch start {
            case .typed:
                lifecycle = .active(id, .readingText(.closed(id.sourceStack)))
                return [.readSelection(id, .editor)]
            case .voice:
                lifecycle = .active(id, .listening(.note(.pending, .closed(id.sourceStack)), .starting))
                return [.show(.voice), .startRecording(id), .readSelection(id, .voice)]
            case let .dictation(_, target):
                lifecycle = .active(id, .listening(.dictation(target), .starting))
                return [.show(.voice), .startRecording(id)]
            }
        case .voicePressed: return pressed(.note)
        case .dictatePressed: return pressed(.dictate)
        case .voiceReleased: return released(.note)
        case .dictateReleased: return released(.dictate)
        case .voiceToggled: return toggled(.note)
        case .dictateToggled: return toggled(.dictate)
        case .voiceRefused:
            consumeHeldRelease()
            return []
        case .voiceEscape:
            guard speech != nil else { return [] }
            consumeHeldRelease()
            return update(.cancelVoice)
        case let .voiceModeChanged(mode):
            voiceMode = mode
            speechLatch = .up
            return speech != nil ? update(.cancelVoice) : []
        default: break
        }
        guard let id = identity, var work else { return [] }
        var effects: [CaptureEffect] = []
        switch event {
        case let .selectionPending(context):
            guard context == id, case let .readingText(choice) = work else { return [] }
            work = .editing(.pending, EditableDraft(body: "", destination: choice))
            effects = [.show(.editor)]
        case let .selection(context, selection):
            guard context == id else { return [] }
            switch work {
            case let .readingText(choice):
                work = .editing(.resolved(selection), EditableDraft(body: "", destination: choice))
                effects = [.show(.editor)]
            case let .editing(.pending, draft): work = .editing(.resolved(selection), draft)
            case let .awaitingTextSelection(draft):
                return save(id, selection: selection, body: draft.body, slot: draft.destination, input: .typed)
            case let .listening(.note(.pending, choice), recording):
                work = .listening(.note(.resolved(selection), choice), recording)
            case let .joiningVoice(slot, preview):
                work = .transcribing(.note(selection, slot), preview)
                effects = [.transcribe(id)]
            default: return []
            }
        case let .recordingStarted(context):
            guard context == id, case let .listening(destination, .starting) = work else { return [] }
            work = .listening(destination, .live(nil))
        case .finishVoice:
            switch work {
            case .listening(_, .starting): return close()
            case let .listening(.note(.pending, choice), .live(preview)):
                work = .joiningVoice(choice.slot, preview)
                effects = [.selectionDeadline(id)]
            case let .listening(.note(.resolved(selection), choice), .live(preview)):
                work = .transcribing(.note(selection, choice.slot), preview)
                effects = [.transcribe(id)]
            case let .listening(.dictation(target), .live(preview)):
                work = .transcribing(.dictation(target), preview)
                effects = [.transcribe(id)]
            default: return []
            }
        case .cancelVoice:
            switch work {
            case .listening, .joiningVoice, .transcribing, .speechFailed: return close()
            default: return []
            }
        case let .changeNote(body):
            guard case let .editing(selection, draft) = work else { return [] }
            work = .editing(selection, EditableDraft(body: body, destination: draft.destination))
        case let .toggleDestinations(context):
            guard context == id, case let .choosing(choice) = destination else { return [] }
            work = choosing(choice.isPickerOpen ? .closed(choice.slot) : .picking(choice.slot), in: work)
        case let .dismissDestinations(context):
            guard context == id, case let .choosing(choice) = destination else { return [] }
            work = choosing(.closed(choice.slot), in: work)
        case let .chooseDestination(context, slot):
            guard context == id, case .choosing(.picking) = destination else { return [] }
            work = choosing(.closed(slot), in: work)
            effects = [.switchStack(slot)]
        case let .stackSelected(slot):
            guard case let .choosing(choice) = destination, choice.slot != slot else { return [] }
            work = choosing(.closed(slot), in: work)
        case .save:
            guard case let .editing(selection, draft) = work else { return [] }
            guard draft.body.nonblank != nil else { return [.beep] }
            switch selection {
            case .pending:
                work = .awaitingTextSelection(FrozenTypedDraft(body: draft.body, destination: draft.destination.slot))
            case let .resolved(selection):
                return save(id, selection: selection, body: draft.body, slot: draft.destination.slot, input: .typed)
            }
        case let .transcript(context, body):
            guard context == id, case let .transcribing(destination, _) = work else { return [] }
            switch destination {
            case let .note(selection, slot): return save(id, selection: selection, body: body, slot: slot, input: .voice)
            case let .dictation(target):
                guard let text = body.nonblank else { return close() }
                work = .inserting(target, text)
                effects = [.insert(id, text, target)]
            }
        case let .voicePartial(context, text):
            guard context == id else { return [] }
            switch work {
            case let .listening(destination, .live): work = .listening(destination, .live(text.nonblank))
            case let .joiningVoice(slot, _): work = .joiningVoice(slot, text.nonblank)
            case let .transcribing(destination, _): work = .transcribing(destination, text.nonblank)
            default: return []
            }
        case let .failed(context, message):
            guard context == id else { return [] }
            switch work {
            case .readingText, .editing(.pending, _), .awaitingTextSelection:
                return update(.selection(id, CapturedSelection(text: "")))
            case .listening, .joiningVoice, .transcribing, .inserting:
                guard let origin = speech?.origin else { return [] }
                work = .speechFailed(origin, message)
                effects = [.failureTimer(id)]
            default: return []
            }
        case let .saved(request, outcome):
            let current: CaptureSaveRequest
            switch work {
            case let .saving(value), let .saveFailed(value, _): current = value
            default: return []
            }
            guard request == current, request.identity == id else { return [] }
            let failure: SaveFailure
            switch outcome {
            case .committed: return close()
            case let .commitFailed(message): failure = .retryable("Couldn’t save the note: \(message)")
            case let .rejected(message): failure = .terminal(message)
            case .cancelled, .noOp: failure = .terminal("The note wasn’t saved.")
            }
            work = .saveFailed(request, failure)
            effects = [.show(.editor)]
        case .retry:
            guard case let .saveFailed(request, .retryable) = work else { return [] }
            work = .saving(request)
            effects = [.retry]
        case let .inserted(context, pasted):
            guard context == id, case let .inserting(target, _) = work else { return [] }
            if pasted { return close() }
            work = .speechFailed(.dictation(target), "Couldn’t paste.")
            effects = [.failureTimer(id)]
        case .dismiss: return close()
        case let .failureTimeout(context):
            guard context == id, case .speechFailed = work else { return [] }
            return close()
        case .begin, .teardown, .voiceRefused, .voicePressed, .voiceReleased, .voiceToggled,
             .dictatePressed, .dictateReleased, .dictateToggled, .voiceEscape, .voiceModeChanged: return []
        }
        lifecycle = .active(id, work)
        return effects
    }

    private func choosing(_ choice: DestinationChoice, in work: CaptureWork) -> CaptureWork {
        switch work {
        case .readingText: return .readingText(choice)
        case let .editing(selection, draft): return .editing(selection, EditableDraft(body: draft.body, destination: choice))
        case let .listening(.note(selection, _), recording): return .listening(.note(selection, choice), recording)
        default: return work
        }
    }

    private mutating func save(_ id: CaptureIdentity, selection: CapturedSelection, body: String,
                               slot: StackSlot, input: NoteInput) -> [CaptureEffect] {
        guard let note = Note.capturing(selection: selection.text, body: body, id: id.noteID, createdAt: id.createdAt)
        else { return input == .voice ? close() : [.beep] }
        let request = CaptureSaveRequest(identity: id, selection: selection, destinationStackID: slot, note: note, input: input)
        lifecycle = .active(id, .saving(request))
        return [.commit(request)]
    }

    private mutating func pressed(_ key: SpeechKey) -> [CaptureEffect] {
        guard speechLatch == .up else { return [] }
        speechLatch = .down(key)
        guard identity != nil else { return [key == .note ? .beginVoice : .beginDictation] }
        speechLatch = .consumeRelease(key)
        return speech?.origin.key == key ? finishOrBeep() : busy()
    }

    private mutating func released(_ key: SpeechKey) -> [CaptureEffect] {
        switch speechLatch {
        case .consumeRelease(key): speechLatch = .up; return []
        case .down(key): speechLatch = .up
        default: return []
        }
        guard voiceMode == .hold, speech?.origin.key == key else { return [] }
        return update(.finishVoice)
    }

    private mutating func toggled(_ key: SpeechKey) -> [CaptureEffect] {
        guard speechLatch == .up else { return [] }
        guard identity != nil else { return [key == .note ? .beginVoice : .beginDictation] }
        return speech?.origin.key == key ? finishOrBeep() : busy()
    }

    private func busy() -> [CaptureEffect] {
        if case .editing = work { return [.focusEditor] }
        if case .awaitingTextSelection = work { return [.focusEditor] }
        return [.beep]
    }

    private mutating func finishOrBeep() -> [CaptureEffect] {
        switch work {
        case .listening, .joiningVoice: return update(.finishVoice)
        default: return [.beep]
        }
    }

    private mutating func consumeHeldRelease() {
        if case let .down(key) = speechLatch { speechLatch = .consumeRelease(key) }
    }

    private mutating func close() -> [CaptureEffect] {
        if speech != nil { consumeHeldRelease() }
        lifecycle = .idle
        return [.close]
    }
}

private extension ResolvedSpeechDestination {
    var origin: SpeechOrigin {
        switch self {
        case let .note(selection, slot): .note(.resolved(selection), slot)
        case let .dictation(target): .dictation(target)
        }
    }
}
