import Foundation
import SendpointDomain

nonisolated struct NoteHighlightState: Equatable {
    private(set) var highlight: UUID?

    mutating func select(_ id: UUID?) {
        highlight = id
    }

    mutating func move(by offset: Int, in ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard let highlight, let index = ids.firstIndex(of: highlight) else {
            self.highlight = offset < 0 ? ids[ids.count - 1] : ids[0]
            return
        }
        self.highlight = ids[wrappedIndex(index, by: offset, count: ids.count)]
    }

    mutating func confine(to ids: [UUID]) {
        if let highlight, ids.contains(highlight) { return }
        highlight = ids.first
    }
}

nonisolated enum PaletteAction: Hashable {
    case clearStack
    case undoClear
    case copyStack
    case chooseTemplate
    case editNote(UUID)
    case copyNote(UUID)
    case deleteNote(UUID)
    case moveNoteUp(UUID)
    case moveNoteDown(UUID)
    case moveNoteToStack(UUID, Int)
}

nonisolated enum PaletteActionSection: Hashable {
    case note
    case stack
    case template

    var label: String {
        switch self {
        case .note: "Note"
        case .stack: "Stack"
        case .template: "Template"
        }
    }
}

nonisolated struct PaletteActionItem: Equatable, Identifiable {
    let action: PaletteAction
    let title: String
    let keys: String
    let section: PaletteActionSection
    var isDestructive = false

    var id: PaletteAction { action }

    var isPinned: Bool {
        switch action {
        case .chooseTemplate, .undoClear: return true
        default: return false
        }
    }
}

nonisolated struct PaletteMoveTarget: Equatable {
    let number: Int
    let keys: String
}

nonisolated struct PaletteActionContext: Equatable {
    enum Focus: Equatable {
        case note(id: UUID, index: Int, count: Int)
        case nothing
    }

    var focus: Focus
    var moveTargets: [PaletteMoveTarget] = []
    var stack: StackItemFacts?
    var undo: StackUndoFacts?
    var templateName: String
}

nonisolated enum PaletteActionCatalog {
    static func items(for context: PaletteActionContext) -> [PaletteActionItem] {
        var items: [PaletteActionItem] = []
        func add(_ action: PaletteAction, _ title: String, _ keys: String,
                 in section: PaletteActionSection, destructive: Bool = false) {
            items.append(PaletteActionItem(action: action, title: title, keys: keys,
                section: section, isDestructive: destructive))
        }

        if case let .note(id, index, count) = context.focus {
            add(.editNote(id), "Edit", "↩", in: .note)
            add(.copyNote(id), "Copy", "⌘C", in: .note)
            if index > 0 { add(.moveNoteUp(id), "Move up", "⌥↑", in: .note) }
            if index < count - 1 { add(.moveNoteDown(id), "Move down", "⌥↓", in: .note) }
            for target in context.moveTargets {
                add(.moveNoteToStack(id, target.number), "Move to \(stackTitle(target.number))", target.keys, in: .note)
            }
            add(.deleteNote(id), "Delete", "⌘⌫", in: .note, destructive: true)
        }
        let hasNotes = context.stack.map { !$0.isEmpty } ?? false
        if hasNotes { add(.copyStack, "Copy as Markdown", "⇧⌘C", in: .stack) }
        if let undo = context.undo { add(.undoClear, undo.title, "⌘Z", in: .stack) }
        if hasNotes { add(.clearStack, "Clear", "⇧⌘⌫", in: .stack, destructive: true) }
        add(.chooseTemplate, "Change template", "⌘P", in: .template)
        return items
    }

    static func menu(_ items: [PaletteActionItem], query: String) -> [PaletteActionItem] {
        items.filter { !$0.isPinned }
            .matching(query) { [$0.title, $0.section.label].joined(separator: " ") }
    }
}

nonisolated enum PaletteKey: Equatable {
    case up, down
    case optionUp, optionDown
    case activate
    case escape
    case commandDelete, shiftCommandDelete
    case commandDigit(Int)
    case moveToStack(Int)
    case command(Character)
    case shiftCommand(Character)
}
