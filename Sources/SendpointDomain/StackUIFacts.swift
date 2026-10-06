import Foundation

func wrappedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
    ((index + offset) % count + count) % count
}

public func noteCountLabel(_ count: Int) -> String {
    "\(count) note\(count == 1 ? "" : "s")"
}

public func stackTitle(_ number: Int) -> String {
    "Stack \(number)"
}

public struct StackItemFacts: Equatable, Identifiable {
    public let id: StackSlot
    public var number: Int { id.number }
    public let noteCount: Int
    public let isCurrent: Bool
    public let startedAt: Date?

    public init(id: StackSlot, noteCount: Int, isCurrent: Bool, startedAt: Date? = nil) {
        self.id = id
        self.noteCount = noteCount
        self.isCurrent = isCurrent
        self.startedAt = startedAt
    }

    public var name: String { stackTitle(number) }
    public var countLabel: String { noteCountLabel(noteCount) }
    public var isEmpty: Bool { noteCount == 0 }
}

public struct StackUndoFacts: Equatable {
    public let stackID: StackSlot
    public var stackName: String { stackTitle(stackID.number) }
    public let noteCount: Int
    public let isCurrentStack: Bool

    public init(stackID: StackSlot, noteCount: Int, isCurrentStack: Bool) {
        self.stackID = stackID
        self.noteCount = noteCount
        self.isCurrentStack = isCurrentStack
    }

    public var notification: String {
        "Cleared \(noteCountLabel(noteCount)) in \(stackName)"
    }

    public var title: String {
        let count = "\(noteCount)"
        return isCurrentStack
            ? "Undo Clear (\(count))"
            : "Undo Clear in \(stackName) (\(count))"
    }
}

public struct StackUIFacts: Equatable {
    public let stacks: [StackItemFacts]
    public let currentStackID: StackSlot
    public let undo: StackUndoFacts?

    @MainActor public init(store: StackStore) {
        self.init(stacks: store.stacks, currentStackID: store.currentStackID, lastCleared: store.lastCleared)
    }

    public init(stacks: [Stack], currentStackID: StackSlot, lastCleared: ClearedBatch?) {
        self.stacks = stacks.map { stack in
            StackItemFacts(
                id: stack.id,
                noteCount: stack.notes.count,
                isCurrent: stack.id == currentStackID,
                startedAt: stack.startedAt
            )
        }
        self.currentStackID = currentStackID

        if let lastCleared {
            undo = StackUndoFacts(
                stackID: lastCleared.stackID,
                noteCount: lastCleared.notes.count,
                isCurrentStack: lastCleared.stackID == currentStackID
            )
        } else {
            undo = nil
        }
    }

    public var current: StackItemFacts? {
        stacks.first(where: { $0.id == currentStackID })
    }

    public func stack(id: StackSlot) -> StackItemFacts? {
        stacks.first(where: { $0.id == id })
    }

    public func stack(number: Int) -> StackItemFacts? {
        stacks.first(where: { $0.number == number })
    }
}
