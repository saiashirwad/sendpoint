import AppKit
import SendpointDomain
import Foundation

/// "1 note", "2 notes": the one spelling of a note count shown to the user.
nonisolated func noteCountLabel(_ count: Int) -> String {
    "\(count) note\(count == 1 ? "" : "s")"
}

/// `index + offset` wrapped into `0..<count`, so stepping past either end of
/// a list continues from the other.
nonisolated func wrappedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
    ((index + offset) % count + count) % count
}

nonisolated struct StackItemFacts: Equatable, Identifiable {
    let id: UUID
    let name: String
    let noteCount: Int
    let isCurrent: Bool

    var countLabel: String { noteCountLabel(noteCount) }
}

nonisolated struct StackUndoFacts: Equatable {
    let stackID: UUID
    let stackName: String
    let noteCount: Int
    let isCurrentStack: Bool

    var title: String {
        let count = "\(noteCount)"
        return isCurrentStack
            ? "Undo Clear (\(count))"
            : "Undo Clear in \(stackName) (\(count))"
    }
}

nonisolated struct StackDeletionFacts: Equatable {
    let liveNoteCount: Int
    let clearedNoteCount: Int

    init(stackID: UUID, stacks: [Stack], lastCleared: ClearedBatch?) {
        liveNoteCount = stacks.stack(id: stackID)?.notes.count ?? 0
        clearedNoteCount = lastCleared?.stackID == stackID
            ? lastCleared?.notes.count ?? 0
            : 0
    }

    var noteCount: Int { liveNoteCount + clearedNoteCount }
    var includesUndoBatch: Bool { clearedNoteCount > 0 }
    var requiresConfirmation: Bool { noteCount > 0 }
}

nonisolated struct StackUIFacts: Equatable {
    let stacks: [StackItemFacts]
    let currentStackID: UUID
    let undo: StackUndoFacts?

    @MainActor init(store: StackStore) {
        self.init(stacks: store.stacks, currentStackID: store.currentStackID, lastCleared: store.lastCleared)
    }

    init(stacks: [Stack], currentStackID: UUID, lastCleared: ClearedBatch?) {
        self.stacks = stacks.map {
            StackItemFacts(
                id: $0.id,
                name: $0.name,
                noteCount: $0.notes.count,
                isCurrent: $0.id == currentStackID
            )
        }
        self.currentStackID = currentStackID

        if let lastCleared, let stack = stacks.stack(id: lastCleared.stackID) {
            undo = StackUndoFacts(
                stackID: stack.id,
                stackName: stack.name,
                noteCount: lastCleared.notes.count,
                isCurrentStack: stack.id == currentStackID
            )
        } else {
            undo = nil
        }
    }

    var current: StackItemFacts? {
        stacks.first(where: { $0.id == currentStackID })
    }

    var currentTitle: String {
        guard let current else { return "Stack Unavailable" }
        return "\(current.name) — \(current.countLabel)"
    }

    var canDelete: Bool { stacks.count > 1 }

    func stack(id: UUID) -> StackItemFacts? {
        stacks.first(where: { $0.id == id })
    }
}

nonisolated enum StackNameValidation: Equatable {
    case valid(String)
    case invalid(String)
}

nonisolated struct StackNameDraft: Equatable {
    var text: String
    let excludedStackID: UUID?

    func validation(stacks: [Stack]) -> StackNameValidation {
        guard let trimmed = text.nonblank else {
            return .invalid("Enter a stack name.")
        }
        guard StackDocumentMutations.isUnique(trimmed, in: stacks, excluding: excludedStackID) else {
            return .invalid("A stack with that name already exists.")
        }
        return .valid(trimmed)
    }
}

/// One row in the stack palette: an existing stack, or the offer to
/// create one named after the current query.
nonisolated enum QuickSwitchRow: Equatable, Hashable {
    case stack(UUID)
    case create(String)
}

/// What the palette lists for a query. Matching is case- and diacritic-
/// insensitive on any part of the name; an empty query lists everything.
nonisolated struct QuickSwitchListing: Equatable {
    let stacks: [StackItemFacts]
    let creatableName: String?

    init(facts: StackUIFacts, query: String) {
        let trimmed = query.nonblank
        let normalizedQuery = query.normalizedName
        stacks = facts.stacks.matching(query, text: \.name)
        let taken = facts.stacks.contains { $0.name.normalizedName == normalizedQuery }
        creatableName = normalizedQuery != nil && !taken ? trimmed : nil
    }

    var rows: [QuickSwitchRow] {
        var rows = stacks.map { QuickSwitchRow.stack($0.id) }
        if let creatableName { rows.append(.create(creatableName)) }
        return rows
    }

    var isEmpty: Bool { rows.isEmpty }
}

nonisolated struct QuickSwitchState: Equatable {
    private(set) var highlight: QuickSwitchRow?

    var selectedStackID: UUID? {
        if case let .stack(id) = highlight { return id }
        return nil
    }

    /// Keeps an explicit stack choice while that stack exists, and
    /// otherwise falls back to the current stack.
    mutating func synchronize(with facts: StackUIFacts) {
        switch highlight {
        case let .stack(id) where facts.stack(id: id) != nil:
            return
        case .create:
            return
        default:
            highlight = .stack(facts.currentStackID)
        }
    }

    mutating func choose(_ stackID: UUID, from facts: StackUIFacts) -> UUID? {
        guard facts.stack(id: stackID) != nil else { return nil }
        highlight = .stack(stackID)
        return stackID
    }

    mutating func selectCurrent(from facts: StackUIFacts) {
        highlight = .stack(facts.currentStackID)
    }

    mutating func highlight(_ row: QuickSwitchRow) {
        highlight = row
    }

    /// Moves the highlight through the listed rows, wrapping at both ends.
    mutating func move(by offset: Int, in rows: [QuickSwitchRow]) {
        guard !rows.isEmpty else { return }
        guard let highlight, let index = rows.firstIndex(of: highlight) else {
            self.highlight = offset < 0 ? rows[rows.count - 1] : rows[0]
            return
        }
        self.highlight = rows[wrappedIndex(index, by: offset, count: rows.count)]
    }

    /// Ensures the highlight names a listed row after the query changes.
    mutating func confine(to rows: [QuickSwitchRow], preferring currentStackID: UUID) {
        if let highlight, rows.contains(highlight) { return }
        if rows.contains(.stack(currentStackID)) {
            highlight = .stack(currentStackID)
        } else {
            highlight = rows.first
        }
    }
}
enum StackDialogs {
    static func confirmsDelete(
        stackID: UUID,
        stacks: [Stack],
        lastCleared: ClearedBatch?
    ) -> Bool {
        guard stacks.count > 1 else {
            showMessage("The last stack cannot be deleted.")
            return false
        }
        guard let stack = stacks.stack(id: stackID) else {
            showMessage("That stack no longer exists.")
            return false
        }
        let deletion = StackDeletionFacts(
            stackID: stackID,
            stacks: stacks,
            lastCleared: lastCleared
        )
        guard deletion.requiresConfirmation else { return true }

        let undoWarning = deletion.includesUndoBatch
            ? " Cleared notes waiting to be undone are deleted too."
            : ""
        return confirmsDeletion(
            of: stack.name,
            informative: "This deletes \(noteCountLabel(deletion.noteCount)).\(undoWarning) This cannot be undone."
        )
    }

    static func showMessage(_ message: String) {
        inform(title: "Couldn't Change Stack", message: message)
    }

    /// A Delete/Cancel warning for `name`; true when Delete was chosen.
    static func confirmsDeletion(of name: String, informative: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = informative
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

func noteStoreErrorMessage(_ error: StackStoreError) -> String {
    switch error {
    case let .mutationRejected(message):
        return message
    case let .commitFailed(message):
        return "Couldn't save the stack change: \(message)"
    case .tornDown:
        return "Stack storage is no longer available."
    }
}
