import Foundation
@testable import SendpointDomain

func filled(_ leading: [Stack]) -> [Stack] {
    StackSlot.allCases.enumerated().map { index, slot in
        Stack(id: slot, notes: index < leading.count ? leading[index].notes : [])
    }
}

extension StackDocument {
    init(stacks: [Stack], currentStackID: StackSlot, lastCleared: ClearedBatch? = nil) {
        self.init()
        for stack in stacks {
            for note in stack.notes {
                guard case let .applied(next) = StackDocumentMutations.applying(.addNote(stackID: stack.id, note: note), to: self) else {
                    preconditionFailure("Invalid fixture")
                }
                self = next
            }
        }
        self.currentStackID = currentStackID
        self.lastCleared = lastCleared
    }
}
