import Foundation

public enum StackDocumentMutation: Equatable, Sendable {
    case switchStack(stackID: StackSlot)
    case addNote(stackID: StackSlot, note: Note)
    case updateNoteBody(stackID: StackSlot, noteID: UUID, body: String, expected: Note? = nil)
    case removeNote(stackID: StackSlot, noteID: UUID)
    case moveNote(stackID: StackSlot, noteID: UUID, destinationIndex: Int)
    case moveNoteToStack(noteID: UUID, from: StackSlot, to: StackSlot)
    case clearStack(stackID: StackSlot)
    case clearExportedNotes(stackID: StackSlot, notes: [Note])
    case undoClear
}

public enum StackDocumentMutationResult: Equatable, Sendable {
    case applied(StackDocument)
    case noOp
    case rejected(String)
}

public enum StackDocumentMutations {
    public static func applying(
        _ mutation: StackDocumentMutation,
        to source: StackDocument
    ) -> StackDocumentMutationResult {
        var document = source
        switch mutation {
        case let .switchStack(slot):
            guard document.currentStackID != slot else { return .noOp }
            document.currentStackID = slot

        case let .addNote(slot, note):
            guard !document[slot].contains(where: { $0.id == note.id }) else {
                return .rejected("The note already exists.")
            }
            document[slot].append(note)

        case let .updateNoteBody(slot, noteID, body, expected):
            guard let index = document[slot].firstIndex(where: { $0.id == noteID }) else {
                return expected == nil ? .noOp : .rejected("The note was moved or deleted. Your draft has been kept.")
            }
            if let expected, document[slot][index] != expected {
                return .rejected("The note changed elsewhere. Your draft has been kept.")
            }
            guard document[slot][index].body != body else { return .noOp }
            document[slot][index].body = body

        case let .removeNote(slot, noteID):
            guard let index = document[slot].firstIndex(where: { $0.id == noteID }) else { return .noOp }
            document[slot].remove(at: index)

        case let .moveNote(slot, noteID, destinationIndex):
            var notes = document[slot]
            guard let sourceIndex = notes.firstIndex(where: { $0.id == noteID }) else {
                return .rejected("The note no longer exists.")
            }
            guard notes.indices.contains(destinationIndex) else {
                return .rejected("The destination is outside the stack.")
            }
            guard sourceIndex != destinationIndex else { return .noOp }
            let note = notes.remove(at: sourceIndex)
            notes.insert(note, at: destinationIndex)
            document[slot] = notes

        case let .moveNoteToStack(noteID, from, to):
            guard from != to else { return .noOp }
            guard let index = document[from].firstIndex(where: { $0.id == noteID }) else {
                return .rejected("The note no longer exists.")
            }
            guard !document[to].contains(where: { $0.id == noteID }) else {
                return .rejected("The note already exists.")
            }
            let note = document[from].remove(at: index)
            document[to].append(note)
            document.currentStackID = to

        case let .clearStack(slot):
            let notes = document[slot]
            guard !notes.isEmpty else { return .noOp }
            document.lastCleared = ClearedBatch(stackID: slot, notes: notes)
            document[slot].removeAll()

        case let .clearExportedNotes(slot, exported):
            let exportedNotes = Set(exported)
            let removed = document[slot].filter { exportedNotes.contains($0) }
            guard !removed.isEmpty else { return .noOp }
            let ids = Set(removed.map(\.id))
            document[slot].removeAll { ids.contains($0.id) }
            document.lastCleared = ClearedBatch(stackID: slot, notes: removed)

        case .undoClear:
            guard let batch = document.lastCleared else { return .noOp }
            let clearedIDs = Set(batch.notes.map(\.id))
            let laterNotes = document[batch.stackID].filter { !clearedIDs.contains($0.id) }
            document[batch.stackID] = batch.notes + laterNotes
            document.lastCleared = nil
        }
        return .applied(document)
    }
}
