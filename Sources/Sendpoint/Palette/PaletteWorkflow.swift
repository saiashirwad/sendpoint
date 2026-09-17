import Foundation
import SendpointDomain

enum PaletteField: Hashable {
    case search, note(UUID), overlay
}

struct PaletteEdit: Equatable {
    let stackID: UUID
    let noteID: UUID
    var text: String
}

enum PaletteOverlay { case actions, templates }

enum PaletteEvent {
    case open, close, teardown, documentChanged
    case query(String), chooseNote(UUID)
    case selectStack(Int)
    case perform(PaletteAction), key(PaletteKey, textHasSelection: Bool)
    case editText(String), commitEdit, cancelEdit, noteFocus(UUID?)
    case toggleOverlay(PaletteOverlay), closeOverlay, overlayQuery(String), overlayHighlight(Int)
    case selectTemplate(UUID), clearFlash(Int), copied(String)
    case mutationResult(UUID, StackMutationOutcome)
    case retry
}

struct PalettePending {
    let id: UUID
    let mutation: StackDocumentMutation
    let stackID: UUID
    let draft: PaletteEdit?
    var continuation: PaletteEvent?
}

enum PaletteInteraction {
    case browsing
    case editing(PaletteEdit)
    case overlay(PaletteOverlay)
    case saving(PalettePending)
    case failed(PalettePending, String, retryable: Bool)
}

struct PaletteWorkflow {
    enum Lifecycle { case closed, open, tornDown }
    var lifecycle: Lifecycle = .closed
    var query = ""
    var shownStackID: UUID?
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
        case .saving, .failed: return true
        default: return false
        }
    }
    mutating func requestFocus(_ field: PaletteField) {
        focusRequest = (field, focusRequest.generation + 1)
    }
}

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

    var shownStack: Stack? {
        context.stacks.stack(id: context.currentStackID)
    }

    var noteListing: NoteListing {
        NoteListing(notes: shownStack?.notes ?? [], query: state.query)
    }

    var highlightedNoteID: UUID? { state.noteState.highlight }

    var activeTemplate: Template { context.activeTemplate }

    var problem: String? {
        guard case let .failed(pending, message, _) = state.interaction else { return nil }
        guard pending.stackID != context.currentStackID,
              let number = context.stacks.number(of: pending.stackID) else { return message }
        return "\(stackTitle(number)): \(message)"
    }

    var actionContext: PaletteActionContext {
        let facts = facts
        let listing = noteListing
        let focus: PaletteActionContext.Focus
        if let id = state.noteState.highlight, let index = listing.ids.firstIndex(of: id) {
            focus = .note(id: id, index: index, count: listing.notes.count)
        } else {
            focus = .nothing
        }
        return PaletteActionContext(
            focus: focus,
            stack: facts.current,
            undo: facts.undo,
            templateName: context.activeTemplate.name
        )
    }

    var actionItems: [PaletteActionItem] {
        PaletteActionCatalog.items(for: actionContext)
    }

    var filteredActionItems: [PaletteActionItem] {
        PaletteActionCatalog.menu(actionItems, query: state.overlayQuery)
    }

    var filteredTemplates: [Template] {
        context.templates.matching(state.overlayQuery, text: \.name)
    }

    var primaryAction: PaletteActionItem? {
        actionItems.first { $0.keys == "↩" }
    }
}

struct PaletteUpdate {
    var state: PaletteWorkflow
    let context: PaletteContext
    let operationID: UUID
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
        case .open:
            if state.lifecycle == .open, finishEdit(before: event) { return true }
            state.lifecycle = .open
            state.interaction = .browsing
            showCurrentStack()
            state.requestFocus(.search)
            return true
        default: guard state.lifecycle == .open else { return true }
        }
        switch event {
        case .documentChanged:
            if state.shownStackID != context.currentStackID {
                if case .editing = state.interaction { finishEdit(before: nil) }
                showCurrentStack()
                if !state.isBusy { state.requestFocus(.search) }
                break
            }
            if !state.isBusy, let edit = state.inlineEdit, !editTargetExists(edit) {
                state.interaction = .browsing
            }
            confine()
        case let .mutationResult(id, outcome): receive(id, outcome)
        case .retry:
            guard case let .failed(pending, _, true) = state.interaction else { break }
            state.interaction = .saving(pending)
            effects.append(.retry)
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
            guard case var .editing(edit) = state.interaction else { break }
            edit.text = text
            state.interaction = .editing(edit)
        case .commitEdit: finishEdit(before: nil)
        case .cancelEdit:
            if case .editing = state.interaction { state.interaction = .browsing; state.requestFocus(.search) }
            if case .failed(_, _, false) = state.interaction { state.interaction = .browsing; state.requestFocus(.search) }
        case let .noteFocus(id):
            if let id { chooseNote(id, editing: true) }
            else if state.inlineEdit != nil { finishEdit(before: nil) }
        case let .chooseNote(id): chooseNote(id, editing: false)
        case let .selectStack(number):
            guard let stack = context.stacks.stack(number: number) else { effects.append(.beep); break }
            guard stack.id != context.currentStackID, !finishEdit(before: event) else { break }
            state.interaction = .browsing
            enqueue(.switchStack(stackID: stack.id))
        case let .perform(action):
            guard !finishEdit(before: event) else { break }
            state.interaction = .browsing
            perform(action)
        case let .toggleOverlay(overlay):
            guard !finishEdit(before: event) else { break }
            if state.overlay == overlay { closeOverlay() } else { openOverlay(overlay) }
        case .closeOverlay: closeOverlay()
        case let .overlayQuery(query): state.overlayQuery = query; state.overlayHighlight = 0
        case let .overlayHighlight(index):
            guard index != state.overlayHighlight else { break }
            state.overlayHighlight = index
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
        let stackID = context.currentStackID
        switch action {
        case .clearStack: enqueue(.clearStack(stackID: stackID))
        case .undoClear: enqueue(.undoClear)
        case .copyStack: effects.append(.copyStack(stackID))
        case .chooseTemplate: openOverlay(.templates)
        case let .editNote(id): chooseNote(id, editing: true)
        case let .copyNote(id):
            if let note = view.noteListing.notes.first(where: { $0.id == id }) { effects.append(.copyNote(note)) }
        case let .deleteNote(id): enqueue(.removeNote(stackID: stackID, noteID: id))
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
        state.noteState.select(id)
        if editing {
            state.interaction = .editing(PaletteEdit(stackID: stack.id, noteID: id, text: note.body))
            state.requestFocus(.note(id))
        }
    }

    private func editTargetExists(_ edit: PaletteEdit) -> Bool {
        context.stacks.stack(id: edit.stackID)?.notes.contains { $0.id == edit.noteID } ?? false
    }

    @discardableResult
    private mutating func finishEdit(before continuation: PaletteEvent?) -> Bool {
        switch state.interaction {
        case var .saving(pending):
            if let continuation { pending.continuation = continuation; state.interaction = .saving(pending) }
            return true
        case .failed: return true
        case .browsing, .overlay: return false
        case let .editing(edit):
            enqueue(.updateNoteBody(stackID: edit.stackID, noteID: edit.noteID, body: edit.text),
                draft: edit, then: continuation)
            return true
        }
    }

    private mutating func enqueue(_ mutation: StackDocumentMutation, draft: PaletteEdit? = nil,
                                 then continuation: PaletteEvent? = nil) {
        state.interaction = .saving(PalettePending(id: operationID, mutation: mutation,
            stackID: draft?.stackID ?? context.currentStackID, draft: draft, continuation: continuation))
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

    private mutating func showCurrentStack() {
        state.shownStackID = context.currentStackID
        state.query = ""
        state.noteState.select(view.noteListing.ids.last)
        confine()
    }

    private mutating func confine() {
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
            case .activate:
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
            state.noteState.move(by: key == .up ? -1 : 1, in: view.noteListing.ids)
        case .escape:
            if !state.query.isEmpty { update(.query("")) }
            else { update(.close) }
        case .command("k"): openOverlay(.actions)
        case .command("p"): openOverlay(.templates)
        case let .commandDigit(digit): update(.selectStack(digit))
        case .activate:
            if let id = state.noteState.highlight { chooseNote(id, editing: true) }
            else { effects.append(.beep) }
        default:
            if key == .command("c"), textHasSelection { return false }
            if key == .commandDelete, !state.query.isEmpty { return false }
            let shortcut: String
            switch key {
            case .command("c"): shortcut = "⌘C"
            case .shiftCommand("c"): shortcut = "⇧⌘C"
            case .command("z"): shortcut = "⌘Z"
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
