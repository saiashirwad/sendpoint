import Foundation
import SendpointDomain

enum PaletteField: Hashable {
    case search, rename(UUID), create, note(UUID), overlay
}

enum PaletteEdit: Equatable {
    case renameStack(id: UUID, text: String, problem: String?)
    case createStack(text: String, problem: String?)
    case note(id: UUID, text: String)

    var noteID: UUID? {
        if case let .note(id, _) = self { return id }
        return nil
    }
    var text: String {
        switch self {
        case let .renameStack(_, text, _), let .createStack(text, _), let .note(_, text): return text
        }
    }
    var problem: String? {
        switch self {
        case let .renameStack(_, _, problem), let .createStack(_, problem): return problem
        case .note: return nil
        }
    }
}

enum PaletteOverlay { case actions, templates }

enum PaletteEvent {
    case open(PaletteLevel), close, teardown, documentChanged
    case query(String), chooseStack(UUID), chooseCreate(String), chooseNote(UUID)
    case perform(PaletteAction), key(PaletteKey, textHasSelection: Bool)
    case editText(String), commitEdit, cancelEdit, noteFocus(UUID?)
    case toggleOverlay(PaletteOverlay), closeOverlay, overlayQuery(String), overlayHighlight(Int)
    case selectProfile(UUID), clearFlash(Int), copied(String)
    case deleteDecision(UUID, confirmed: Bool)
    case mutationResult(UUID, AnnotationStoreMutationOutcome)
    case retry
}

struct PalettePending {
    let id: UUID
    let mutation: SessionDocumentMutation
    let draft: PaletteEdit?
    var continuation: PaletteEvent?
}

enum PaletteInteraction {
    case browsing
    case editing(PaletteEdit)
    case overlay(PaletteOverlay)
    case confirmingDelete(UUID)
    case saving(PalettePending)
    case failed(PalettePending, String, retryable: Bool)
}

struct PaletteWorkflow {
    enum Lifecycle { case closed, open, tornDown }
    var lifecycle: Lifecycle = .closed
    var level: PaletteLevel = .stacks
    var query = ""
    var stackState = QuickSwitchState()
    var noteState = NoteHighlightState()
    var interaction: PaletteInteraction = .browsing
    var overlayQuery = ""
    var overlayHighlight = 0
    var focusRequest: (field: PaletteField, generation: Int) = (.search, 0)
    var flash: (text: String, generation: Int)?
    var nextFlash = 0

    var inlineEdit: PaletteEdit? {
        switch interaction {
        case let .editing(edit): return edit
        case let .saving(pending), let .failed(pending, _, _): return pending.draft
        default: return nil
        }
    }
    var overlay: PaletteOverlay? {
        if case let .overlay(overlay) = interaction { return overlay }
        return nil
    }
    var isBusy: Bool {
        switch interaction {
        case .saving, .failed, .confirmingDelete: return true
        default: return false
        }
    }
    var problem: String? {
        if case let .failed(_, message, _) = interaction { return message }
        return inlineEdit?.problem
    }
    mutating func focus(_ field: PaletteField) {
        focusRequest = (field, focusRequest.generation + 1)
    }
}

/// Read-only input for one update/render, never another mutable document owner.
struct PaletteContext {
    let sessions: [Session]
    let currentSessionID: UUID
    let lastCleared: ClearedBatch?
    let profiles: [Profile]
    let activeProfile: Profile
}

enum PaletteEffect {
    case mutate(UUID, SessionDocumentMutation)
    case retry
    case confirmDelete(UUID)
    case copyStack(UUID)
    case copyNote(Annotation)
    case selectProfile(UUID)
    case openURL(URL)
    case close
    case beep
}

struct PaletteProjection {
    let state: PaletteWorkflow
    let context: PaletteContext
    // MARK: - Derived

    var facts: SessionUIFacts {
        SessionUIFacts(
            sessions: context.sessions,
            currentSessionID: context.currentSessionID,
            lastCleared: context.lastCleared
        )
    }

    var stackListing: QuickSwitchListing {
        QuickSwitchListing(facts: facts, query: state.level == .stacks ? state.query : "")
    }

    /// The stack whose notes are shown: the open one, or the highlighted one
    /// as a preview.
    var shownSession: Session? {
        switch state.level {
        case let .notes(id):
            return context.sessions.first(where: { $0.id == id })
        case .stacks:
            guard let id = state.stackState.selectedSessionID else { return nil }
            return context.sessions.first(where: { $0.id == id })
        }
    }

    var noteListing: NoteListing {
        NoteListing(entries: shownSession?.entries ?? [], query: state.level == .stacks ? "" : state.query)
    }

    var highlightedNoteID: UUID? {
        guard case .notes = state.level else { return nil }
        return state.noteState.highlight
    }

    var isEditingNote: Bool { state.inlineEdit?.noteID != nil }

    var activeProfile: Profile { context.activeProfile }

    var actionContext: PaletteActionContext {
        let facts = facts
        let focus: PaletteActionContext.Focus
        switch state.level {
        case .stacks:
            switch state.stackState.highlight {
            case let .session(id):
                if let session = facts.session(id: id) {
                    focus = .stack(
                        id: id, name: session.name, isCurrent: session.isCurrent,
                        noteCount: session.annotationCount)
                } else {
                    focus = .nothing
                }
            case let .create(name):
                focus = .createStack(name: name)
            case nil:
                focus = .nothing
            }
        case .notes:
            let listing = noteListing
            if let id = state.noteState.highlight, let index = listing.ids.firstIndex(of: id) {
                focus = .note(
                    id: id, index: index, count: listing.entries.count,
                    sourceURL: listing.entries[index].provenance.url)
            } else {
                focus = .nothing
            }
        }
        let open = state.level.sessionID.flatMap { facts.session(id: $0) }.map {
            (id: $0.id, name: $0.name, isCurrent: $0.isCurrent, noteCount: $0.annotationCount)
        }
        return PaletteActionContext(
            level: state.level,
            focus: focus,
            openStack: open,
            canDeleteStack: facts.canDelete,
            undo: facts.undo,
            templateName: context.activeProfile.name
        )
    }

    var actionItems: [PaletteActionItem] {
        PaletteActionCatalog.items(for: actionContext)
    }

    var filteredActionItems: [PaletteActionItem] {
        PaletteActionCatalog.filter(actionItems, query: state.overlayQuery)
    }

    var filteredProfiles: [Profile] {
        let trimmed = state.overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let needle = SessionDocumentMutations.normalizedSessionName(trimmed) else {
            return context.profiles
        }
        return context.profiles.filter {
            (SessionDocumentMutations.normalizedSessionName($0.name) ?? "").contains(needle)
        }
    }

    /// The action ↩ performs, for the footer.
    var primaryAction: PaletteActionItem? {
        actionItems.first { $0.keys == "↩" }
    }

}

/// All palette events reduce synchronously against the latest committed document.
/// UUID/time are supplied by the owner, so transitions are deterministic in tests.
struct PaletteUpdate {
    var state: PaletteWorkflow
    let context: PaletteContext
    let operationID: UUID
    let now: Date
    private(set) var effects: [PaletteEffect] = []
    private var view: PaletteProjection { PaletteProjection(state: state, context: context) }

    @discardableResult
    mutating func update(_ event: PaletteEvent) -> Bool {
        guard state.lifecycle != .tornDown else { return true }
        switch event {
        case .teardown:
            state.lifecycle = .tornDown
            effects.append(.close)
            return true
        case let .open(level):
            if state.lifecycle == .open, finishEdit(before: event) { return true }
            state.lifecycle = .open
            state.interaction = .browsing
            navigate(level)
            return true
        default: guard state.lifecycle == .open else { return true }
        }
        switch event {
        case .documentChanged:
            if let id = state.level.sessionID, !context.sessions.contains(where: { $0.id == id }) {
                // Keep a pending draft until its exact mutation reports rejection.
                if !state.isBusy { state.interaction = .browsing; navigate(.stacks) }
            }
            state.stackState.synchronize(with: view.facts)
            confine()
        case let .mutationResult(id, outcome): receive(id, outcome)
        case .retry:
            guard case let .failed(pending, _, true) = state.interaction else { break }
            state.interaction = .saving(pending)
            effects.append(.retry)
        case let .deleteDecision(id, confirmed):
            guard case .confirmingDelete(id) = state.interaction else { break }
            state.interaction = .browsing
            if confirmed { enqueue(.deleteSession(sessionID: id)) }
        case .close:
            if finishEdit(before: event) { break }
            state.lifecycle = .closed
            effects.append(.close)
        case let .key(key, selected): return handle(key, textHasSelection: selected)
        case let .query(query):
            guard !state.isBusy, state.inlineEdit == nil else { break }
            state.query = query
            confine()
        case let .editText(text):
            guard case let .editing(edit) = state.interaction else { break }
            switch edit {
            case let .renameStack(id, _, _): state.interaction = .editing(.renameStack(id: id, text: text, problem: nil))
            case .createStack: state.interaction = .editing(.createStack(text: text, problem: nil))
            case let .note(id, _): state.interaction = .editing(.note(id: id, text: text))
            }
        case .commitEdit: _ = finishEdit(before: nil)
        case .cancelEdit:
            if case .editing = state.interaction { state.interaction = .browsing; state.focus(.search) }
            if case .failed(_, _, false) = state.interaction { state.interaction = .browsing; state.focus(.search) }
        case let .noteFocus(id):
            if let id { chooseNote(id, editing: true) }
            else if state.inlineEdit?.noteID != nil { _ = finishEdit(before: nil) }
        case let .chooseStack(id):
            guard !state.isBusy, state.inlineEdit == nil, state.level == .stacks else { break }
            _ = state.stackState.choose(id, from: view.facts)
        case let .chooseCreate(name):
            guard !state.isBusy, state.inlineEdit == nil, state.level == .stacks else { break }
            state.stackState.highlight(.create(name))
        case let .chooseNote(id): chooseNote(id, editing: false)
        case let .perform(action):
            guard !finishEdit(before: event) else { break }
            state.interaction = .browsing
            perform(action)
        case let .toggleOverlay(overlay):
            guard !finishEdit(before: event) else { break }
            if state.overlay == overlay { closeOverlay() } else { openOverlay(overlay) }
        case .closeOverlay: closeOverlay()
        case let .overlayQuery(query): state.overlayQuery = query; state.overlayHighlight = 0
        case let .overlayHighlight(index): state.overlayHighlight = index
        case let .selectProfile(id):
            guard !finishEdit(before: event) else { break }
            closeOverlay()
            effects.append(.selectProfile(id))
        case let .copied(text):
            state.nextFlash += 1
            state.flash = (text, state.nextFlash)
        case let .clearFlash(generation):
            if state.flash?.generation == generation { state.flash = nil }
        case .open, .teardown: break
        }
        return true
    }

    private mutating func perform(_ action: PaletteAction) {
        switch action {
        case let .switchToStack(id): enqueue(.switchSession(sessionID: id), then: .close)
        case let .openStack(id): navigate(.notes(id))
        case .backToStacks: navigate(.stacks)
        case .newStack:
            state.interaction = .editing(.createStack(text: view.stackListing.creatableName ?? "", problem: nil))
            state.focus(.create)
        case let .createStack(name):
            state.interaction = .editing(.createStack(text: name, problem: nil))
            _ = finishEdit(before: .close)
        case let .renameStack(id):
            guard let session = view.facts.session(id: id) else { break }
            state.interaction = .editing(.renameStack(id: id, text: session.name, problem: nil))
            state.focus(.rename(id))
        case let .deleteStack(id):
            guard view.facts.canDelete else { effects.append(.beep); break }
            state.interaction = .confirmingDelete(id)
            effects.append(.confirmDelete(id))
        case let .clearStack(id): enqueue(.clearSession(sessionID: id))
        case .undoClear: enqueue(.undoClear)
        case let .copyStack(id): effects.append(.copyStack(id))
        case .chooseTemplate: openOverlay(.templates)
        case let .editNote(id): chooseNote(id, editing: true)
        case let .copyNote(id):
            if let note = view.noteListing.entries.first(where: { $0.id == id }) { effects.append(.copyNote(note)) }
        case let .deleteNote(id):
            if let sessionID = state.level.sessionID { enqueue(.removeAnnotation(sessionID: sessionID, annotationID: id)) }
        case let .moveNoteUp(id): moveNote(id, offset: -1)
        case let .moveNoteDown(id): moveNote(id, offset: 1)
        case let .openSource(url): effects.append(.openURL(url)); _ = update(.close)
        }
    }

    private mutating func chooseNote(_ id: UUID, editing: Bool) {
        guard state.level.sessionID != nil, let note = view.noteListing.entries.first(where: { $0.id == id }) else { return }
        if state.inlineEdit?.noteID == id { return }
        let next: PaletteEvent = editing ? .perform(.editNote(id)) : .chooseNote(id)
        guard !finishEdit(before: next) else { return }
        state.noteState.select(id)
        if editing { state.interaction = .editing(.note(id: id, text: note.note)); state.focus(.note(id)) }
    }

    /// Navigation waits for the draft's own commit. Focus loss never drops it.
    private mutating func finishEdit(before continuation: PaletteEvent?) -> Bool {
        switch state.interaction {
        case var .saving(pending):
            if let continuation { pending.continuation = continuation; state.interaction = .saving(pending) }
            return true
        case .failed, .confirmingDelete: return true
        case .browsing, .overlay: return false
        case let .editing(edit):
            let mutation: SessionDocumentMutation
            switch edit {
            case let .note(id, text):
                guard let sessionID = state.level.sessionID else { return true }
                mutation = .updateAnnotationNote(sessionID: sessionID, annotationID: id, note: text)
            case let .renameStack(_, text, _), let .createStack(text, _):
                let excluded: UUID?
                if case let .renameStack(id, _, _) = edit { excluded = id } else { excluded = nil }
                switch SessionNameDraft(text: text, excludedSessionID: excluded).validation(sessions: context.sessions) {
                case let .invalid(problem):
                    state.interaction = .editing(excluded.map { .renameStack(id: $0, text: text, problem: problem) }
                        ?? .createStack(text: text, problem: problem))
                    effects.append(.beep)
                    return true
                case let .valid(name):
                    mutation = excluded.map { .renameSession(sessionID: $0, name: name) }
                        ?? .createSession(Session(id: operationID, name: name, createdAt: now))
                }
            }
            enqueue(mutation, draft: edit, then: continuation)
            return true
        }
    }

    private mutating func enqueue(_ mutation: SessionDocumentMutation, draft: PaletteEdit? = nil,
                                 then continuation: PaletteEvent? = nil) {
        state.interaction = .saving(PalettePending(id: operationID, mutation: mutation,
            draft: draft, continuation: continuation))
        effects.append(.mutate(operationID, mutation))
    }

    private mutating func receive(_ id: UUID, _ outcome: AnnotationStoreMutationOutcome) {
        let pending: PalettePending
        switch state.interaction {
        case let .saving(value), let .failed(value, _, _): pending = value
        default: return
        }
        guard pending.id == id else { return }
        switch outcome {
        case .committed, .noOp:
            state.interaction = .browsing
            state.focus(.search)
            confine()
            if let next = pending.continuation { _ = update(next) }
        case let .commitFailed(message): state.interaction = .failed(pending, message, retryable: true)
        case let .rejected(message): state.interaction = .failed(pending, message, retryable: false)
        case .cancelled: state.interaction = .failed(pending, "Saving was cancelled.", retryable: false)
        }
    }

    private mutating func navigate(_ level: PaletteLevel) {
        state.level = level.sessionID.map { id in
            context.sessions.contains(where: { $0.id == id }) ? level : .stacks
        } ?? .stacks
        state.query = ""
        if state.level == .stacks { state.stackState.selectCurrent(from: view.facts) }
        else { state.noteState.select(nil) }
        confine()
        state.focus(.search)
    }
    private mutating func confine() {
        state.stackState.confine(to: view.stackListing.rows, preferring: context.currentSessionID)
        state.noteState.confine(to: view.noteListing.ids)
    }
    private mutating func moveNote(_ id: UUID, offset: Int) {
        guard let session = view.shownSession, let index = session.entries.firstIndex(where: { $0.id == id }),
              session.entries.indices.contains(index + offset) else { effects.append(.beep); return }
        enqueue(.moveAnnotation(sessionID: session.id, annotationID: id, destinationIndex: index + offset))
    }
    private mutating func openOverlay(_ overlay: PaletteOverlay) {
        state.interaction = .overlay(overlay)
        state.overlayQuery = ""
        state.overlayHighlight = overlay == .templates
            ? context.profiles.firstIndex(where: { $0.id == context.activeProfile.id }) ?? 0 : 0
        state.focus(.overlay)
    }
    private mutating func closeOverlay() {
        guard state.overlay != nil else { return }
        state.interaction = .browsing
        state.overlayQuery = ""
        state.focus(.search)
    }

    private mutating func handle(_ key: PaletteKey, textHasSelection: Bool) -> Bool {
        if state.isBusy {
            if key == .escape { _ = update(.cancelEdit) }
            return true
        }
        if let overlay = state.overlay {
            let count = overlay == .actions ? view.filteredActionItems.count : view.filteredProfiles.count
            switch key {
            case .up, .down:
                if count > 0 { state.overlayHighlight = (state.overlayHighlight + (key == .up ? -1 : 1) + count) % count }
            case .activate, .commandActivate:
                let index = state.overlayHighlight
                if overlay == .actions, view.filteredActionItems.indices.contains(index) {
                    _ = update(.perform(view.filteredActionItems[index].action))
                } else if overlay == .templates, view.filteredProfiles.indices.contains(index) {
                    _ = update(.selectProfile(view.filteredProfiles[index].id))
                }
            case .escape: closeOverlay()
            case .command("k"): _ = update(.toggleOverlay(.actions))
            case .command("p"): _ = update(.toggleOverlay(.templates))
            case .command, .shiftCommand, .commandDelete, .shiftCommandDelete, .optionUp, .optionDown, .commandDigit:
                closeOverlay()
                return handle(key, textHasSelection: false)
            default: return false
            }
            return true
        }
        if state.inlineEdit != nil {
            switch key {
            case .activate: _ = update(.commitEdit)
            case .escape: _ = update(.cancelEdit)
            case .command("k"): _ = update(.toggleOverlay(.actions))
            default: return false
            }
            return true
        }
        switch key {
        case .up, .down:
            let offset = key == .up ? -1 : 1
            if state.level == .stacks { state.stackState.move(by: offset, in: view.stackListing.rows) }
            else { state.noteState.move(by: offset, in: view.noteListing.ids) }
        case .escape:
            if !state.query.isEmpty { _ = update(.query("")) }
            else if state.level != .stacks { navigate(.stacks) }
            else { _ = update(.close) }
        case .command("k"): openOverlay(.actions)
        case .command("p"): openOverlay(.templates)
        case let .commandDigit(digit):
            let index = digit - 1
            if state.level == .stacks, view.stackListing.sessions.indices.contains(index) {
                _ = update(.perform(.switchToStack(view.stackListing.sessions[index].id)))
            } else if view.noteListing.ids.indices.contains(index) {
                state.noteState.select(view.noteListing.ids[index])
            }
        case .activate, .commandActivate:
            if state.level == .stacks {
                switch state.stackState.highlight {
                case let .session(id): _ = update(.perform(.switchToStack(id)))
                case let .create(name): _ = update(.perform(.createStack(name)))
                case nil: effects.append(.beep)
                }
            } else if key == .commandActivate, let id = state.level.sessionID {
                _ = update(.perform(.switchToStack(id)))
            } else if let id = state.noteState.highlight { chooseNote(id, editing: true) }
        case .tab, .right:
            guard key == .tab || state.query.isEmpty else { return false }
            guard state.level == .stacks, let id = state.stackState.selectedSessionID else { return false }
            navigate(.notes(id))
        case .backTab, .left, .delete:
            guard key == .backTab || state.query.isEmpty else { return false }
            guard state.level != .stacks else { return false }
            navigate(.stacks)
        default:
            if key == .command("c"), textHasSelection { return false }
            if key == .commandDelete, !state.query.isEmpty { return false }
            let shortcut: String
            switch key {
            case .command("c"): shortcut = "⌘C"
            case .shiftCommand("c"): shortcut = state.level == .stacks ? "⌘C" : "⇧⌘C"
            case .command("z"): shortcut = "⌘Z"
            case .command("r"): shortcut = "⌘R"
            case .command("n"): shortcut = "⌘N"
            case .command("o"): shortcut = "⌘O"
            case .commandDelete: shortcut = "⌘⌫"
            case .shiftCommandDelete: shortcut = "⇧⌘⌫"
            case .optionUp: shortcut = "⌥↑"
            case .optionDown: shortcut = "⌥↓"
            default: return false
            }
            if let item = view.actionItems.first(where: { $0.keys == shortcut }) { _ = update(.perform(item.action)) }
            else { effects.append(.beep) }
        }
        return true
    }
}
