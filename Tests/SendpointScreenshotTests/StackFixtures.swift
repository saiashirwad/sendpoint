import SendpointDomain

extension StackDocument {
    init(stacks: [Stack]) {
        self.init()
        for stack in stacks {
            for note in stack.notes {
                guard case let .applied(next) = StackDocumentMutations.applying(.addNote(stackID: stack.id, note: note), to: self) else {
                    preconditionFailure("Invalid fixture")
                }
                self = next
            }
        }
    }
}
