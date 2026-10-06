import SendpointDomain

extension StackDocument {
    init(stacks: [Stack], currentStackID: StackSlot) {
        self.init()
        for stack in stacks {
            for note in stack.notes {
                guard case let .applied(next) = StackDocumentMutations.applying(.addNote(stackID: stack.id, note: note), to: self) else {
                    preconditionFailure("Invalid fixture")
                }
                self = next
            }
        }
        if case let .applied(next) = StackDocumentMutations.applying(.switchStack(stackID: currentStackID), to: self) {
            self = next
        }
    }
}
