import Foundation
import SendpointDomain

/// Where the palette is: the list of every stack, or inside one of them.
enum PaletteLevel: Equatable, Hashable {
    case stacks
    case notes(UUID)

    var sessionID: UUID? {
        if case let .notes(id) = self { return id }
        return nil
    }
}

/// Which note carries the keyboard highlight inside a stack.
struct NoteHighlightState: Equatable {
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
        let count = ids.count
        self.highlight = ids[((index + offset) % count + count) % count]
    }

    /// Ensures the highlight names a listed note after the listing changes.
    mutating func confine(to ids: [UUID]) {
        if let highlight, ids.contains(highlight) { return }
        highlight = ids.first
    }
}

/// Everything the palette can do from the keyboard or the ⌘K menu.
enum PaletteAction: Hashable {
    case switchToStack(UUID)
    case openStack(UUID)
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
    case openSource(URL)
    case backToStacks
}

/// One entry of the ⌘K menu: the action, how it reads, and its keys.
struct PaletteActionItem: Equatable, Identifiable {
    let action: PaletteAction
    let title: String
    let keys: String
    var subtitle: String? = nil
    var isDestructive = false

    var id: PaletteAction { action }
}

/// What the palette is looking at, reduced to what decides the action list.
struct PaletteActionContext: Equatable {
    enum Focus: Equatable {
        case stack(SessionItemFacts)
        case createStack(name: String)
        case note(id: UUID, index: Int, count: Int, sourceURL: URL?)
        case nothing
    }

    var level: PaletteLevel
    var focus: Focus
    /// The stack the notes level is inside, when it is.
    var openStack: SessionItemFacts?
    var canDeleteStack: Bool
    var undo: SessionUndoFacts?
    var templateName: String
}

/// The ⌘K menu, derived from context so the footer, the menu, and the key
/// handler all agree on what is possible right now.
enum PaletteActionCatalog {
    static func items(for context: PaletteActionContext) -> [PaletteActionItem] {
        var items: [PaletteActionItem] = []
        func add(_ action: PaletteAction, _ title: String, _ keys: String,
                 subtitle: String? = nil, destructive: Bool = false) {
            items.append(PaletteActionItem(action: action, title: title, keys: keys,
                subtitle: subtitle, isDestructive: destructive))
        }
        func template() { add(.chooseTemplate, "Template: \(context.templateName)", "⌘P") }
        func undo() { if let undo = context.undo { add(.undoClear, undo.title, "⌘Z") } }
        func copy(_ stack: SessionItemFacts, keys: String) {
            guard stack.annotationCount > 0 else { return }
            add(.copyStack(stack.id), "Copy “\(stack.name)” as Markdown", keys,
                subtitle: "Shaped by the \(context.templateName) template")
        }
        func clear(_ stack: SessionItemFacts) {
            guard stack.annotationCount > 0 else { return }
            add(.clearStack(stack.id), "Clear “\(stack.name)”", "⇧⌘⌫",
                subtitle: "Sets the notes aside; undo with ⌘Z", destructive: true)
        }

        switch context.level {
        case .stacks:
            switch context.focus {
            case let .stack(stack):
                add(.switchToStack(stack.id),
                    stack.isCurrent ? "Keep “\(stack.name)” current" : "Switch to “\(stack.name)”", "↩")
                add(.openStack(stack.id), "Open “\(stack.name)”", "→")
                copy(stack, keys: "⌘C")
                add(.renameStack(stack.id), "Rename “\(stack.name)”", "⌘R")
                add(.newStack, "New Stack", "⌘N")
                template()
                undo()
                clear(stack)
                if context.canDeleteStack {
                    add(.deleteStack(stack.id), "Delete “\(stack.name)”", "⌘⌫", destructive: true)
                }
            case let .createStack(name):
                add(.createStack(name), "Create “\(name)”", "↩")
                template()
            case .note, .nothing:
                add(.newStack, "New Stack", "⌘N")
                template()
                undo()
            }
        case .notes:
            if case let .note(id, index, count, sourceURL) = context.focus {
                add(.editNote(id), "Edit Note", "↩")
                add(.copyNote(id), "Copy Note", "⌘C")
                if let sourceURL {
                    add(.openSource(sourceURL), "Open Source", "⌘O",
                        subtitle: sourceURL.host ?? sourceURL.absoluteString)
                }
                if index > 0 { add(.moveNoteUp(id), "Move Note Up", "⌥↑") }
                if index < count - 1 { add(.moveNoteDown(id), "Move Note Down", "⌥↓") }
                add(.deleteNote(id), "Delete Note", "⌘⌫", destructive: true)
            }
            if let stack = context.openStack {
                if !stack.isCurrent { add(.switchToStack(stack.id), "Switch to “\(stack.name)”", "⌘↩") }
                copy(stack, keys: "⇧⌘C")
                add(.renameStack(stack.id), "Rename “\(stack.name)”", "⌘R")
            }
            template()
            add(.backToStacks, "All Stacks", "←")
            undo()
            if let stack = context.openStack { clear(stack) }
        }
        return items
    }

    /// The ⌘K menu narrowed by what was typed into it.
    static func filter(_ items: [PaletteActionItem], query: String) -> [PaletteActionItem] {
        items.matching(query) { [$0.title, $0.subtitle ?? ""].joined(separator: " ") }
    }
}

/// The keys the palette claims ahead of its text fields.
enum PaletteKey: Equatable {
    case up, down, left, right
    case optionUp, optionDown
    case tab, backTab
    case activate, commandActivate
    case escape
    case delete, commandDelete, shiftCommandDelete
    case commandDigit(Int)
    case command(Character)
    case shiftCommand(Character)
}
