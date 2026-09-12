import Foundation
import SendpointDomain

enum PaletteField: Hashable {
    case search, rename(UUID), create, note(UUID), overlay
}

enum PaletteEdit: Equatable {
    case renameStack(id: UUID, text: String, problem: String?)
    case createStack(text: String, problem: String?)
    case note(stackID: UUID, id: UUID, text: String)

    var noteID: UUID? {
        if case let .note(_, id, _) = self { return id }
        return nil
    }
    var stackID: UUID? {
        if case let .note(stackID, _, _) = self { return stackID }
        return nil
    }
    var text: String {
        switch self {
        case let .renameStack(_, text, _), let .createStack(text, _), let .note(_, _, text): return text
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
    case open(PalettePane, highlighting: UUID?), close, teardown, documentChanged
    case query(String), chooseStack(UUID), chooseCreate(String), chooseNote(UUID), focusPane(PalettePane)
    case perform(PaletteAction), key(PaletteKey, textHasSelection: Bool)
    case editText(String), commitEdit, cancelEdit, noteFocus(UUID?)
    case toggleOverlay(PaletteOverlay), closeOverlay, overlayQuery(String), overlayHighlight(Int)
    case selectTemplate(UUID), clearFlash(Int), copied(String)
    case deleteDecision(UUID, confirmed: Bool)
    case mutationResult(UUID, StackMutationOutcome)
    case retry
}

struct PalettePending {
    let id: UUID
    let mutation: StackDocumentMutation
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
    var focusedPane: PalettePane = .stacks
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
    mutating func requestFocus(_ field: PaletteField) {
        focusRequest = (field, focusRequest.generation + 1)
    }
}

/// Read-only input for one update/render, never another mutable document owner.
struct PaletteContext {
    let stacks: [Stack]
    let currentStackID: UUID
    let lastCleared: ClearedBatch?
    let templates: [Template]
    let activeTemplate: Template
}

enum PaletteEffect {
    case mutate(UUID, StackDocumentMutation)
    case retry
    case confirmDelete(UUID)
    case copyStack(UUID)
    case copyNote(Note)
    case selectTemplate(UUID)
    case close
    case beep
}

struct PaletteProjection {
    let state: PaletteWorkflow
    let context: PaletteContext
    // MARK: - Derived

    var facts: StackUIFacts {
        StackUIFacts(stacks: context.stacks, currentStackID: context.currentStackID,
            lastCleared: context.lastCleared)
    }

    var stackListing: QuickSwitchListing {
        QuickSwitchListing(facts: facts, query: state.focusedPane == .stacks ? state.query : "")
    }

    /// The stack whose notes the note pane shows: the sidebar highlight.
    var shownStack: Stack? {
        state.stackState.selectedStackID.flatMap { context.stacks.stack(id: $0) }
    }

    var noteListing: NoteListing {
        NoteListing(notes: shownStack?.notes ?? [], query: state.focusedPane == .notes ? state.query : "")
    }

    var searchPlaceholder: String {
        switch state.focusedPane {
        case .stacks: "Find or create a stack"
        case .notes: shownStack.map { "Search notes in \($0.name)" } ?? "Search notes"
        }
    }

    var highlightedNoteID: UUID? { state.noteState.highlight }

    var activeTemplate: Template { context.activeTemplate }

    var actionContext: PaletteActionContext {
        let facts = facts
        let focus: PaletteActionContext.Focus
        switch state.focusedPane {
        case .stacks:
            switch state.stackState.highlight {
            case let .stack(id): focus = facts.stack(id: id).map { .stack($0) } ?? .nothing
            case let .create(name): focus = .createStack(name: name)
            case nil: focus = .nothing
            }
        case .notes:
            let listing = noteListing
            if let id = state.noteState.highlight, let index = listing.ids.firstIndex(of: id) {
                focus = .note(id: id, index: index, count: listing.notes.count)
            } else {
                focus = .nothing
            }
        }
        return PaletteActionContext(
            pane: state.focusedPane,
            focus: focus,
            shownStack: state.stackState.selectedStackID.flatMap { facts.stack(id: $0) },
            canDeleteStack: facts.canDelete,
            undo: facts.undo,
            templateName: context.activeTemplate.name
        )
    }

    var actionItems: [PaletteActionItem] {
        PaletteActionCatalog.items(for: actionContext)
    }

    var filteredActionItems: [PaletteActionItem] {
        PaletteActionCatalog.filter(actionItems, query: state.overlayQuery)
    }

    var filteredTemplates: [Template] {
        context.templates.matching(state.overlayQuery, text: \.name)
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
        case let .open(pane, stackID):
            if state.lifecycle == .open, finishEdit(before: event) { return true }
            state.lifecycle = .open
            state.interaction = .browsing
            open(pane, highlighting: stackID)
            return true
        default: guard state.lifecycle == .open else { return true }
        }
        switch event {
        case .documentChanged:
            let shownBefore = view.shownStack?.id
            state.stackState.synchronize(with: view.facts)
            if view.shownStack?.id != shownBefore {
                state.noteState.select(view.noteListing.ids.last)
            }
            // A draft whose stack vanished cannot be shown anywhere. A draft
            // already on its way to the store is kept until its result lands.
            if !state.isBusy, let edit = state.inlineEdit, !editTargetExists(edit) {
                state.interaction = .browsing
            }
            confine()
        case let .mutationResult(id, outcome): receive(id, outcome)
        case .retry:
            guard case let .failed(pending, _, true) = state.interaction else { break }
            state.interaction = .saving(pending)
            effects.append(.retry)
        case let .deleteDecision(id, confirmed):
            guard case .confirmingDelete(id) = state.interaction else { break }
            state.interaction = .browsing
            if confirmed { enqueue(.deleteStack(stackID: id)) }
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
            case let .note(stackID, id, _): state.interaction = .editing(.note(stackID: stackID, id: id, text: text))
            }
        case .commitEdit: finishEdit(before: nil)
        case .cancelEdit:
            if case .editing = state.interaction { state.interaction = .browsing; state.requestFocus(.search) }
            if case .failed(_, _, false) = state.interaction { state.interaction = .browsing; state.requestFocus(.search) }
        case let .noteFocus(id):
            if let id { chooseNote(id, editing: true) }
            else if state.inlineEdit?.noteID != nil { finishEdit(before: nil) }
        case let .chooseStack(id):
            guard !state.isBusy, state.inlineEdit == nil, view.facts.stack(id: id) != nil else { break }
            if state.focusedPane != .stacks { state.focusedPane = .stacks; state.query = "" }
            _ = state.stackState.choose(id, from: view.facts)
            state.noteState.select(view.noteListing.ids.last)
            confine()
        case let .chooseCreate(name):
            guard !state.isBusy, state.inlineEdit == nil else { break }
            if state.focusedPane != .stacks { state.focusedPane = .stacks; state.query = "" }
            state.stackState.highlight(.create(name))
            state.noteState.select(nil)
        case let .chooseNote(id): chooseNote(id, editing: false)
        case let .focusPane(pane):
            guard pane != state.focusedPane, !state.isBusy, state.inlineEdit == nil else { break }
            state.focusedPane = pane
            state.query = ""
            confine()
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
        case let .selectTemplate(id):
            guard !finishEdit(before: event) else { break }
            closeOverlay()
            effects.append(.selectTemplate(id))
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
        case let .switchToStack(id): enqueue(.switchStack(stackID: id), then: .close)
        case .newStack:
            let draft = state.focusedPane == .stacks ? view.stackListing.creatableName ?? "" : ""
            state.focusedPane = .stacks
            state.query = ""
            state.interaction = .editing(.createStack(text: draft, problem: nil))
            state.requestFocus(.create)
        case let .createStack(name):
            state.interaction = .editing(.createStack(text: name, problem: nil))
            finishEdit(before: .close)
        case let .renameStack(id):
            guard let stack = view.facts.stack(id: id) else { break }
            state.focusedPane = .stacks
            state.query = ""
            state.interaction = .editing(.renameStack(id: id, text: stack.name, problem: nil))
            state.requestFocus(.rename(id))
        case let .deleteStack(id):
            guard view.facts.canDelete else { effects.append(.beep); break }
            state.interaction = .confirmingDelete(id)
            effects.append(.confirmDelete(id))
        case let .clearStack(id): enqueue(.clearStack(stackID: id))
        case .undoClear: enqueue(.undoClear)
        case let .copyStack(id): effects.append(.copyStack(id))
        case .chooseTemplate: openOverlay(.templates)
        case let .editNote(id): chooseNote(id, editing: true)
        case let .copyNote(id):
            if let note = view.noteListing.notes.first(where: { $0.id == id }) { effects.append(.copyNote(note)) }
        case let .deleteNote(id):
            if let stackID = view.shownStack?.id { enqueue(.removeNote(stackID: stackID, noteID: id)) }
        case let .moveNoteUp(id): moveNote(id, offset: -1)
        case let .moveNoteDown(id): moveNote(id, offset: 1)
        }
    }

    private mutating func chooseNote(_ id: UUID, editing: Bool) {
        guard let stack = view.shownStack,
              let note = view.noteListing.notes.first(where: { $0.id == id }) else { return }
        if state.inlineEdit?.noteID == id { return }
        let next: PaletteEvent = editing ? .perform(.editNote(id)) : .chooseNote(id)
        guard !finishEdit(before: next) else { return }
        if state.focusedPane != .notes { state.focusedPane = .notes; state.query = "" }
        state.noteState.select(id)
        if editing {
            state.interaction = .editing(.note(stackID: stack.id, id: id, text: note.body))
            state.requestFocus(.note(id))
        }
    }

    /// Whether an unsaved draft still names something in the document.
    private func editTargetExists(_ edit: PaletteEdit) -> Bool {
        switch edit {
        case let .note(stackID, noteID, _):
            return context.stacks.stack(id: stackID)?.notes.contains { $0.id == noteID } ?? false
        case let .renameStack(id, _, _):
            return context.stacks.contains { $0.id == id }
        case .createStack:
            return true
        }
    }

    /// Navigation waits for the draft's own commit. Focus loss never drops it.
    @discardableResult
    private mutating func finishEdit(before continuation: PaletteEvent?) -> Bool {
        switch state.interaction {
        case var .saving(pending):
            if let continuation { pending.continuation = continuation; state.interaction = .saving(pending) }
            return true
        case .failed, .confirmingDelete: return true
        case .browsing, .overlay: return false
        case let .editing(edit):
            let mutation: StackDocumentMutation
            switch edit {
            case let .note(stackID, id, text):
                mutation = .updateNoteBody(stackID: stackID, noteID: id, body: text)
            case let .renameStack(_, text, _), let .createStack(text, _):
                let excluded: UUID?
                if case let .renameStack(id, _, _) = edit { excluded = id } else { excluded = nil }
                switch StackNameDraft(text: text, excludedStackID: excluded).validation(stacks: context.stacks) {
                case let .invalid(problem):
                    state.interaction = .editing(excluded.map { .renameStack(id: $0, text: text, problem: problem) }
                        ?? .createStack(text: text, problem: problem))
                    effects.append(.beep)
                    return true
                case let .valid(name):
                    mutation = excluded.map { .renameStack(stackID: $0, name: name) }
                        ?? .createStack(Stack(id: operationID, name: name, createdAt: now))
                }
            }
            enqueue(mutation, draft: edit, then: continuation)
            return true
        }
    }

    private mutating func enqueue(_ mutation: StackDocumentMutation, draft: PaletteEdit? = nil,
                                 then continuation: PaletteEvent? = nil) {
        state.interaction = .saving(PalettePending(id: operationID, mutation: mutation,
            draft: draft, continuation: continuation))
        effects.append(.mutate(operationID, mutation))
    }

    private mutating func receive(_ id: UUID, _ outcome: StackMutationOutcome) {
        let pending: PalettePending
        switch state.interaction {
        case let .saving(value), let .failed(value, _, _): pending = value
        default: return
        }
        guard pending.id == id else { return }
        switch outcome {
        case .committed, .noOp:
            state.interaction = .browsing
            state.requestFocus(.search)
            confine()
            if let next = pending.continuation { update(next) }
        case let .commitFailed(message): state.interaction = .failed(pending, message, retryable: true)
        case let .rejected(message): state.interaction = .failed(pending, message, retryable: false)
        case .cancelled: state.interaction = .failed(pending, "Saving was cancelled.", retryable: false)
        }
    }

    /// Opens on a pane, with the sidebar highlight on `stackID` when it is
    /// still there, and the newest note ready.
    private mutating func open(_ pane: PalettePane, highlighting stackID: UUID?) {
        state.focusedPane = pane
        state.query = ""
        if let stackID, view.facts.stack(id: stackID) != nil {
            _ = state.stackState.choose(stackID, from: view.facts)
        } else {
            state.stackState.selectCurrent(from: view.facts)
        }
        state.noteState.select(view.noteListing.ids.last)
        confine()
        state.requestFocus(.search)
    }

    /// Tab and the arrow keys flip which pane owns the keyboard. Each pane
    /// keeps its own highlight; only the query resets.
    private mutating func toggleFocus() {
        switch state.focusedPane {
        case .stacks:
            guard view.shownStack != nil else { return }
            if state.noteState.highlight == nil {
                state.noteState.select(view.noteListing.ids.last)
            }
            state.focusedPane = .notes
        case .notes:
            state.focusedPane = .stacks
        }
        state.query = ""
        confine()
        state.requestFocus(.search)
    }

    private mutating func confine() {
        state.stackState.confine(to: view.stackListing.rows, preferring: context.currentStackID)
        state.noteState.confine(to: view.noteListing.ids)
    }
    private mutating func moveNote(_ id: UUID, offset: Int) {
        guard let stack = view.shownStack, let index = stack.notes.firstIndex(where: { $0.id == id }),
              stack.notes.indices.contains(index + offset) else { effects.append(.beep); return }
        enqueue(.moveNote(stackID: stack.id, noteID: id, destinationIndex: index + offset))
    }
    private mutating func openOverlay(_ overlay: PaletteOverlay) {
        state.interaction = .overlay(overlay)
        state.overlayQuery = ""
        state.overlayHighlight = overlay == .templates
            ? context.templates.firstIndex(where: { $0.id == context.activeTemplate.id }) ?? 0 : 0
        state.requestFocus(.overlay)
    }
    private mutating func closeOverlay() {
        guard state.overlay != nil else { return }
        state.interaction = .browsing
        state.overlayQuery = ""
        state.requestFocus(.search)
    }

    private mutating func handle(_ key: PaletteKey, textHasSelection: Bool) -> Bool {
        if state.isBusy {
            if key == .escape { update(.cancelEdit) }
            return true
        }
        if let overlay = state.overlay {
            let count = overlay == .actions ? view.filteredActionItems.count : view.filteredTemplates.count
            switch key {
            case .up, .down:
                if count > 0 { state.overlayHighlight = wrappedIndex(state.overlayHighlight, by: key == .up ? -1 : 1, count: count) }
            case .activate, .commandActivate:
                let index = state.overlayHighlight
                if overlay == .actions, view.filteredActionItems.indices.contains(index) {
                    update(.perform(view.filteredActionItems[index].action))
                } else if overlay == .templates, view.filteredTemplates.indices.contains(index) {
                    update(.selectTemplate(view.filteredTemplates[index].id))
                }
            case .escape: closeOverlay()
            case .command("k"): update(.toggleOverlay(.actions))
            case .command("p"): update(.toggleOverlay(.templates))
            case .command, .shiftCommand, .commandDelete, .shiftCommandDelete, .optionUp, .optionDown, .commandDigit:
                closeOverlay()
                return handle(key, textHasSelection: false)
            default: return false
            }
            return true
        }
        if state.inlineEdit != nil {
            switch key {
            case .activate: update(.commitEdit)
            case .escape: update(.cancelEdit)
            case .command("k"): update(.toggleOverlay(.actions))
            default: return false
            }
            return true
        }
        switch key {
        case .up, .down:
            let offset = key == .up ? -1 : 1
            if state.focusedPane == .stacks {
                state.stackState.move(by: offset, in: view.stackListing.rows)
                state.noteState.select(view.noteListing.ids.last)
            } else {
                state.noteState.move(by: offset, in: view.noteListing.ids)
            }
        case .escape:
            if !state.query.isEmpty { update(.query("")) }
            else { update(.close) }
        case .command("k"): openOverlay(.actions)
        case .command("p"): openOverlay(.templates)
        case let .commandDigit(digit):
            let index = digit - 1
            if view.stackListing.stacks.indices.contains(index) {
                update(.perform(.switchToStack(view.stackListing.stacks[index].id)))
            }
        case .activate, .commandActivate:
            if state.focusedPane == .stacks {
                switch state.stackState.highlight {
                case let .stack(id): update(.perform(.switchToStack(id)))
                case let .create(name): update(.perform(.createStack(name)))
                case nil: effects.append(.beep)
                }
            } else if key == .commandActivate, let id = view.shownStack?.id {
                update(.perform(.switchToStack(id)))
            } else if let id = state.noteState.highlight { chooseNote(id, editing: true) }
        case .tab, .backTab, .left, .right:
            guard key == .tab || key == .backTab || state.query.isEmpty else { return false }
            toggleFocus()
        default:
            if key == .command("c"), textHasSelection { return false }
            if key == .commandDelete, !state.query.isEmpty { return false }
            let shortcut: String
            switch key {
            case .command("c"): shortcut = "⌘C"
            case .shiftCommand("c"): shortcut = state.focusedPane == .stacks ? "⌘C" : "⇧⌘C"
            case .command("z"): shortcut = "⌘Z"
            case .command("r"): shortcut = "⌘R"
            case .command("n"): shortcut = "⌘N"
            case .commandDelete: shortcut = "⌘⌫"
            case .shiftCommandDelete: shortcut = "⇧⌘⌫"
            case .optionUp: shortcut = "⌥↑"
            case .optionDown: shortcut = "⌥↓"
            default: return false
            }
            if let item = view.actionItems.first(where: { $0.keys == shortcut }) { update(.perform(item.action)) }
            else { effects.append(.beep) }
        }
        return true
    }
}
