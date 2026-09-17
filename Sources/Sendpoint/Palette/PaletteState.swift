import Foundation
import SendpointDomain

/// Which pane owns the keyboard: the stack sidebar or the note list.
nonisolated enum PalettePane: Equatable, Hashable {
    case stacks
    case notes
}

/// Which note carries the keyboard highlight inside a stack.
nonisolated struct NoteHighlightState: Equatable {
    private(set) var highlight: UUID?

    mutating func select(_ id: UUID?) {
        highlight = id
    }

    /// Moves the highlight through the listed notes, wrapping at both ends.
    mutating func move(by offset: Int, in ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard let highlight, let index = ids.firstIndex(of: highlight) else {
            self.highlight = offset < 0 ? ids[ids.count - 1] : ids[0]
            return
        }
        self.highlight = ids[wrappedIndex(index, by: offset, count: ids.count)]
    }

    /// Ensures the highlight names a listed note after the listing changes.
    mutating func confine(to ids: [UUID]) {
        if let highlight, ids.contains(highlight) { return }
        highlight = ids.first
    }
}

/// Everything the palette can do from the keyboard or the ⌘K menu.
nonisolated enum PaletteAction: Hashable {
    case switchToStack(UUID)
    case createStack(String)
    case newStack
    case renameStack(UUID)
    case deleteStack(UUID)
    case clearStack(UUID)
    case undoClear
    case copyStack(UUID)
    case chooseTemplate
    case editNote(UUID)
    case copyNote(UUID)
    case deleteNote(UUID)
    case moveNoteUp(UUID)
    case moveNoteDown(UUID)
}

/// Which part of the palette a ⌘K entry acts on. The menu groups by this,
/// so titles can be plain verbs.
nonisolated enum PaletteActionSection: Hashable {
    case note
    case stack(name: String?)
    case template

    var label: String {
        switch self {
        case .note: "Note"
        case .stack: "Stack"
        case .template: "Template"
        }
    }

    var detail: String? {
        if case let .stack(name) = self { return name }
        return nil
    }
}

/// One entry of the ⌘K menu: the action, how it reads, and its keys.
nonisolated struct PaletteActionItem: Equatable, Identifiable {
    let action: PaletteAction
    let title: String
    let keys: String
    let section: PaletteActionSection
    var isDestructive = false

    var id: PaletteAction { action }

    /// Whether the palette already shows this action's keys somewhere on
    /// its own chrome: the footer, the sidebar, the undo banner. Those stay
    /// out of the ⌘K menu, which lists only what has no other home.
    var isPinned: Bool {
        if keys == "↩" { return true }
        switch action {
        case .chooseTemplate, .newStack, .undoClear: return true
        default: return false
        }
    }

    /// One word for the footer.
    var verb: String {
        switch action {
        case .switchToStack: title.hasPrefix("Keep") ? "Keep" : "Switch"
        case .createStack: "Create"
        default: title
        }
    }
}

/// What the palette is looking at, reduced to what decides the action list.
nonisolated struct PaletteActionContext: Equatable {
    enum Focus: Equatable {
        case stack(StackItemFacts)
        case createStack(name: String)
        case note(id: UUID, index: Int, count: Int)
        case nothing
    }

    var pane: PalettePane
    var focus: Focus
    /// The stack the note pane shows: the sidebar highlight.
    var shownStack: StackItemFacts?
    var canDeleteStack: Bool
    var undo: StackUndoFacts?
    var templateName: String
}

/// The ⌘K menu, derived from context so the footer, the menu, and the key
/// handler all agree on what is possible right now.
nonisolated enum PaletteActionCatalog {
    static func items(for context: PaletteActionContext) -> [PaletteActionItem] {
        var items: [PaletteActionItem] = []
        func add(_ action: PaletteAction, _ title: String, _ keys: String,
                 in section: PaletteActionSection, destructive: Bool = false) {
            items.append(PaletteActionItem(action: action, title: title, keys: keys,
                section: section, isDestructive: destructive))
        }
        func template() { add(.chooseTemplate, "Change template", "⌘P", in: .template) }
        func undo(in section: PaletteActionSection) {
            if let undo = context.undo { add(.undoClear, undo.title, "⌘Z", in: section) }
        }
        func copy(_ stack: StackItemFacts, keys: String) {
            guard stack.noteCount > 0 else { return }
            add(.copyStack(stack.id), "Copy as Markdown", keys, in: .stack(name: stack.name))
        }
        func clear(_ stack: StackItemFacts) {
            guard stack.noteCount > 0 else { return }
            add(.clearStack(stack.id), "Clear", "⇧⌘⌫", in: .stack(name: stack.name), destructive: true)
        }
        func stackActions(_ stack: StackItemFacts, switchKeys: String, copyKeys: String,
                          showsCurrent: Bool) {
            let section = PaletteActionSection.stack(name: stack.name)
            if showsCurrent || !stack.isCurrent {
                add(.switchToStack(stack.id), stack.isCurrent ? "Keep current" : "Switch", switchKeys, in: section)
            }
            copy(stack, keys: copyKeys)
            add(.renameStack(stack.id), "Rename", "⌘R", in: section)
            add(.newStack, "New stack", "⌘N", in: section)
            undo(in: section)
            clear(stack)
        }

        switch context.focus {
        case let .stack(stack):
            stackActions(stack, switchKeys: "↩", copyKeys: "⌘C", showsCurrent: true)
            if context.canDeleteStack {
                add(.deleteStack(stack.id), "Delete", "⌘⌫", in: .stack(name: stack.name), destructive: true)
            }
            template()
        case let .createStack(name):
            add(.createStack(name), "Create “\(name)”", "↩", in: .stack(name: nil))
            template()
        case let .note(id, index, count):
            add(.editNote(id), "Edit", "↩", in: .note)
            add(.copyNote(id), "Copy", "⌘C", in: .note)
            if index > 0 { add(.moveNoteUp(id), "Move up", "⌥↑", in: .note) }
            if index < count - 1 { add(.moveNoteDown(id), "Move down", "⌥↓", in: .note) }
            add(.deleteNote(id), "Delete", "⌘⌫", in: .note, destructive: true)
            if let stack = context.shownStack {
                stackActions(stack, switchKeys: "⌘↩", copyKeys: "⇧⌘C", showsCurrent: false)
            } else {
                undo(in: .stack(name: nil))
            }
            template()
        case .nothing:
            if context.pane == .notes, let stack = context.shownStack {
                stackActions(stack, switchKeys: "⌘↩", copyKeys: "⇧⌘C", showsCurrent: false)
            } else {
                add(.newStack, "New stack", "⌘N", in: .stack(name: nil))
                undo(in: .stack(name: nil))
            }
            template()
        }
        return items
    }

    /// What the ⌘K menu lists: the unpinned actions, narrowed by what was
    /// typed. A section's name counts, so "note" or "stack" finds a group.
    static func menu(_ items: [PaletteActionItem], query: String) -> [PaletteActionItem] {
        items.filter { !$0.isPinned }
            .matching(query) { [$0.title, $0.section.label, $0.section.detail ?? ""].joined(separator: " ") }
    }
}

/// The keys the palette claims ahead of its text fields.
nonisolated enum PaletteKey: Equatable {
    case up, down, left, right
    case optionUp, optionDown
    case tab, backTab
    case activate, commandActivate
    case escape
    case commandDelete, shiftCommandDelete
    case commandDigit(Int)
    case command(Character)
    case shiftCommand(Character)
}

/// Where keyboard focus sits in the palette panel, reduced to what decides
/// key ownership between the global monitor and the row-section move
/// handlers. The window controller maps `panel.firstResponder` to this; pure
/// code never touches AppKit. A focused row Button presents as a non-text
/// responder, while every TextField (search, rename, note editor, overlay
/// filter) presents as its NSTextField or as the NSTextView field editor.
nonisolated enum PaletteResponderKind: Equatable {
    /// NSTextField / NSTextView, including the field editor.
    case text
    /// Any other responder: a focused row Button, palette chrome, or an
    /// unknown hosting subview. Indistinguishable by kind, so the decline
    /// predicate treats all of them as "focus in rows" (see below).
    case control
    /// No first responder.
    case none
}

/// Single-fire key routing between the palette's global local monitor and
/// the row sections' `.onMoveCommand` handlers. Pure: the monitor's AppKit
/// read (`panel.firstResponder` kind) enters only through `responder`, and
/// workflow facts enter as scalars, so every case is unit-testable.
nonisolated enum PaletteKeyRouting {
    /// Whether the global monitor must DECLINE `key` (return the event
    /// unhandled) so the focused row section owns it via `.onMoveCommand`.
    /// Exactly one owner results by construction: declined keys are sent to
    /// the reducer only by the view handler; every other key goes to the
    /// reducer only through the monitor.
    ///
    /// The decline set is deliberately arrows-only (up/down/left/right):
    /// - Tab/backTab stay monitor-owned in every focus state. No view-side
    ///   Tab owner exists (`.onMoveCommand` covers arrows only), so declining
    ///   Tab would strand pane-toggle semantics in the responder chain and
    ///   desync `focusedPane` from the model. Narrower and safe wins.
    /// - Return/Escape/command/option keys stay monitor-owned in every focus
    ///   state (see the monitor: a local monitor runs before the responder
    ///   chain, so consuming there guarantees a focused Button never also
    ///   activates — no select+perform double-fire).
    /// - `responder` must be `.control`: text editors keep today's monitor
    ///   behavior exactly, and `.none` keeps it too (a nil responder means
    ///   focus is nowhere the row handlers can see).
    /// - `inlineEditActive` / `overlayOpen` force monitor ownership, keeping
    ///   today's inline-edit and overlay fall-through behavior bit-for-bit.
    /// - `cycling` forces monitor ownership (the monitor already bypasses
    ///   cycling entirely; the flag keeps this function total for tests).
    ///
    /// Residual edge: `.control` also covers non-row chrome Buttons (header
    /// clear, undo banner). With focus parked on one of those, arrows decline
    /// to the responder chain and no-op instead of moving the highlight, as
    /// they do today. Tab/Return/Escape stay monitor-owned, so one keystroke
    /// always recovers (Tab flips panes and refocuses search).
    static func shouldDeclineForRowFocus(
        key: PaletteKey,
        responder: PaletteResponderKind,
        inlineEditActive: Bool,
        overlayOpen: Bool,
        cycling: Bool
    ) -> Bool {
        guard !cycling, !overlayOpen, !inlineEditActive else { return false }
        guard responder == .control else { return false }
        switch key {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}
