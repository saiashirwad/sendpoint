import Foundation

public enum StackDocumentMutation: Equatable, Sendable {
    case switchStack(stackID: UUID)
    case addNote(stackID: UUID, note: Note)
    case updateNoteBody(stackID: UUID, noteID: UUID, body: String)
    case removeNote(stackID: UUID, noteID: UUID)

    case moveNote(stackID: UUID, noteID: UUID, destinationIndex: Int)
    case moveNoteToStack(noteID: UUID, from: UUID, to: UUID)
    case clearStack(stackID: UUID)
    case clearExportedNotes(stackID: UUID, notes: [Note])
    case undoClear
}

public enum StackDocumentMutationResult: Equatable, Sendable {
    case applied(StackDocument)
    case noOp
    case rejected(String)
}

public struct StackDocumentValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public enum StackDocumentMutations {
    public static func validate(_ document: StackDocument) throws {
        guard document.version == StackDocument.currentVersion else {
            throw StackDocumentValidationError("unsupported document version: \(document.version)")
        }
        guard document.stacks.count == StackDocument.stackCount else {
            throw StackDocumentValidationError("a document holds exactly \(StackDocument.stackCount) stacks")
        }
        guard Set(document.stacks.map(\.id)).count == document.stacks.count else {
            throw StackDocumentValidationError("stack IDs must be unique")
        }
        guard document.stacks.contains(where: { $0.id == document.currentStackID }) else {
            throw StackDocumentValidationError("currentStackID must identify a stack")
        }

        for stack in document.stacks {
            guard Set(stack.notes.map(\.id)).count == stack.notes.count else {
                throw StackDocumentValidationError("note IDs must be unique within a stack")
            }
        }

        if let batch = document.lastCleared {
            guard !batch.notes.isEmpty else {
                throw StackDocumentValidationError("lastCleared must not be empty")
            }
            guard document.stacks.contains(where: { $0.id == batch.stackID }) else {
                throw StackDocumentValidationError("lastCleared must identify a stack")
            }
            guard Set(batch.notes.map(\.id)).count == batch.notes.count else {
                throw StackDocumentValidationError("lastCleared note IDs must be unique")
            }
        }
    }

    public static func applying(
        _ mutation: StackDocumentMutation,
        to source: StackDocument
    ) -> StackDocumentMutationResult {
        do {
            try validate(source)
        } catch {
            return .rejected("The stack document is invalid: \(error)")
        }

        var document = source
        switch mutation {
        case let .switchStack(stackID):
            guard stackIndex(stackID, in: document) != nil else {
                return .rejected("The stack no longer exists.")
            }
            guard document.currentStackID != stackID else { return .noOp }
            document.currentStackID = stackID

        case let .addNote(stackID, note):
            guard let stackIndex = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            guard !document.stacks[stackIndex].notes.contains(where: { $0.id == note.id }) else {
                return .rejected("The note already exists.")
            }
            document.stacks[stackIndex].notes.append(note)

        case let .updateNoteBody(stackID, noteID, note):
            guard let stackIndex = stackIndex(stackID, in: document),
                  let noteIndex = document.stacks[stackIndex].notes.firstIndex(where: {
                      $0.id == noteID
                  })
            else { return .noOp }
            guard document.stacks[stackIndex].notes[noteIndex].body != note else {
                return .noOp
            }
            document.stacks[stackIndex].notes[noteIndex].body = note

        case let .removeNote(stackID, noteID):
            guard let stackIndex = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            guard let noteIndex = document.stacks[stackIndex].notes.firstIndex(where: {
                $0.id == noteID
            }) else {
                return .noOp
            }
            document.stacks[stackIndex].notes.remove(at: noteIndex)

        case let .moveNote(stackID, noteID, destinationIndex):
            guard let stackIndex = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            var notes = document.stacks[stackIndex].notes
            guard let sourceIndex = notes.firstIndex(where: { $0.id == noteID }) else {
                return .rejected("The note no longer exists.")
            }
            guard notes.indices.contains(destinationIndex) else {
                return .rejected("The destination is outside the stack.")
            }
            guard sourceIndex != destinationIndex else { return .noOp }
            let note = notes.remove(at: sourceIndex)
            notes.insert(note, at: destinationIndex)
            document.stacks[stackIndex].notes = notes

        case let .moveNoteToStack(noteID, from, to):
            guard let sourceIndex = stackIndex(from, in: document),
                  let destinationIndex = stackIndex(to, in: document)
            else { return .rejected("The stack no longer exists.") }
            guard from != to else { return .noOp }
            guard let noteIndex = document.stacks[sourceIndex].notes.firstIndex(where: { $0.id == noteID }) else {
                return .rejected("The note no longer exists.")
            }
            guard !document.stacks[destinationIndex].notes.contains(where: { $0.id == noteID }) else {
                return .rejected("The note already exists.")
            }
            let note = document.stacks[sourceIndex].notes.remove(at: noteIndex)
            document.stacks[destinationIndex].notes.append(note)
            document.currentStackID = to

        case let .clearStack(stackID):
            guard let stackIndex = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            let notes = document.stacks[stackIndex].notes
            guard !notes.isEmpty else { return .noOp }
            document.lastCleared = ClearedBatch(stackID: stackID, notes: notes)
            document.stacks[stackIndex].notes.removeAll()

        case let .clearExportedNotes(stackID, exported):
            guard let index = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            let removed = document.stacks[index].notes.filter { note in
                exported.contains { snapshot in
                    snapshot.id == note.id && snapshot.body == note.body
                        && snapshot.subject == note.subject && snapshot.createdAt == note.createdAt
                }
            }
            guard !removed.isEmpty else { return .noOp }
            let ids = Set(removed.map(\.id))
            document.stacks[index].notes.removeAll { ids.contains($0.id) }
            document.lastCleared = ClearedBatch(stackID: stackID, notes: removed)

        case .undoClear:
            guard let batch = document.lastCleared else { return .noOp }
            guard let stackIndex = stackIndex(batch.stackID, in: document) else {
                return .rejected("The cleared stack no longer exists.")
            }
            let clearedIDs = Set(batch.notes.map(\.id))
            let entriesAddedAfterClear = document.stacks[stackIndex].notes.filter {
                !clearedIDs.contains($0.id)
            }
            document.stacks[stackIndex].notes = batch.notes + entriesAddedAfterClear
            document.lastCleared = nil
        }

        do {
            try validate(document)
        } catch {
            return .rejected("The mutation would create an invalid stack document: \(error)")
        }
        return .applied(document)
    }

    private static func stackIndex(_ id: UUID, in document: StackDocument) -> Int? {
        document.stacks.firstIndex(where: { $0.id == id })
    }
}
