import Foundation

public nonisolated struct NoteHighlightState: Equatable {
    public private(set) var highlight: UUID?

    public init() {}

    mutating func select(_ id: UUID?) {
        highlight = id
    }

    public mutating func move(by offset: Int, in ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard let highlight, let index = ids.firstIndex(of: highlight) else {
            self.highlight = offset < 0 ? ids[ids.count - 1] : ids[0]
            return
        }
        self.highlight = ids[wrappedIndex(index, by: offset, count: ids.count)]
    }

    public mutating func confine(to ids: [UUID]) {
        if let highlight, ids.contains(highlight) { return }
        highlight = ids.first
    }
}

public nonisolated enum PaletteAction: Hashable {
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

public nonisolated enum PaletteActionSection: Hashable {
    case note
    case stack
    case template

    public var label: String {
        switch self {
        case .note: "Note"
        case .stack: "Stack"
        case .template: "Template"
        }
    }
}

public nonisolated struct PaletteActionItem: Equatable, Identifiable {
    public let action: PaletteAction
    public let title: String
    public let keys: String
    public let section: PaletteActionSection
    public var isDestructive = false

    public init(
        action: PaletteAction,
        title: String,
        keys: String,
        section: PaletteActionSection,
        isDestructive: Bool = false
    ) {
        self.action = action
        self.title = title
        self.keys = keys
        self.section = section
        self.isDestructive = isDestructive
    }

    public var id: PaletteAction { action }

    var isPinned: Bool {
        switch action {
        case .chooseTemplate, .undoClear: return true
        default: return false
        }
    }
}

public nonisolated struct PaletteMoveTarget: Equatable {
    public let number: Int
    public let keys: String

    public init(number: Int, keys: String) {
        self.number = number
        self.keys = keys
    }
}

public nonisolated struct PaletteActionContext: Equatable {
    public enum Focus: Equatable {
        case note(id: UUID, index: Int, count: Int)
        case nothing
    }

    public var focus: Focus
    public var moveTargets: [PaletteMoveTarget] = []
    public var stack: StackItemFacts?
    public var undo: StackUndoFacts?

    public init(
        focus: Focus,
        moveTargets: [PaletteMoveTarget] = [],
        stack: StackItemFacts? = nil,
        undo: StackUndoFacts? = nil
    ) {
        self.focus = focus
        self.moveTargets = moveTargets
        self.stack = stack
        self.undo = undo
    }
}

public nonisolated enum PaletteActionCatalog {
    public static func items(for context: PaletteActionContext) -> [PaletteActionItem] {
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

    public static func menu(_ items: [PaletteActionItem], query: String) -> [PaletteActionItem] {
        items.filter { !$0.isPinned }
            .matching(query) { [$0.title, $0.section.label].joined(separator: " ") }
    }
}

public nonisolated enum PaletteKey: Equatable {
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
