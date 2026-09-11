import Foundation

/// Every supported change to a stack document.
public enum StackDocumentMutation: Equatable, Sendable {
    case createStack(Stack)
    case renameStack(stackID: UUID, name: String)
    case switchStack(stackID: UUID)
    case deleteStack(stackID: UUID)
    case addNote(stackID: UUID, note: Note)
    case updateNoteBody(stackID: UUID, noteID: UUID, body: String)
    case updateNoteProvenance(
        stackID: UUID,
        noteID: UUID,
        expectedApplication: ApplicationIdentity,
        provenance: Provenance
    )
    case removeNote(stackID: UUID, noteID: UUID)

    /// Moves an note to a final zero-based index in its stack.
    case moveNote(stackID: UUID, noteID: UUID, destinationIndex: Int)
    case clearStack(stackID: UUID)
    case clearExportedNotes(stackID: UUID, notes: [Note])
    case undoClear
}

/// The result of applying a pure document mutation.
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

/// Pure stack document rules. This type has no UI or persistence dependency.
public enum StackDocumentMutations {
    /// Trims a name and returns its case-, diacritic-, and width-insensitive key.
    public static func normalizedStackName(_ name: String) -> String? {
        name.normalizedStackName
    }

    public static func validate(_ document: StackDocument) throws {
        guard document.version == StackDocument.currentVersion else {
            throw StackDocumentValidationError("unsupported document version: \(document.version)")
        }
        guard !document.stacks.isEmpty else {
            throw StackDocumentValidationError("stacks must not be empty")
        }
        guard Set(document.stacks.map(\.id)).count == document.stacks.count else {
            throw StackDocumentValidationError("stack IDs must be unique")
        }
        guard document.stacks.contains(where: { $0.id == document.currentStackID }) else {
            throw StackDocumentValidationError("currentStackID must identify a stack")
        }

        var names = Set<String>()
        for stack in document.stacks {
            let trimmed = stack.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard stack.name == trimmed, let nameKey = normalizedStackName(stack.name) else {
                throw StackDocumentValidationError("stack names must be trimmed and nonempty")
            }
            guard names.insert(nameKey).inserted else {
                throw StackDocumentValidationError("stack names must be unique")
            }
            guard Set(stack.notes.map(\.id)).count == stack.notes.count else {
                throw StackDocumentValidationError("note IDs must be unique within a stack")
            }
        }

        guard Set(document.recentStackIDs).count == document.recentStackIDs.count else {
            throw StackDocumentValidationError("recentStackIDs must be unique")
        }
        for id in document.recentStackIDs where !document.stacks.contains(where: { $0.id == id }) {
            throw StackDocumentValidationError("recentStackIDs must identify stacks")
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
        case var .createStack(stack):
            stack.name = stack.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedStackName(stack.name) != nil else {
                return .rejected("Stack names must not be empty.")
            }
            guard !document.stacks.contains(where: { $0.id == stack.id }) else {
                return .rejected("A stack with that identifier already exists.")
            }
            guard isUnique(stack.name, in: document.stacks) else {
                return .rejected("Stack names must be unique.")
            }
            guard Set(stack.notes.map(\.id)).count == stack.notes.count else {
                return .rejected("Note identifiers must be unique within a stack.")
            }
            document.stacks.append(stack)
            document.currentStackID = stack.id
            document.touchStack(stack.id)

        case let .renameStack(stackID, name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedStackName(trimmed) != nil else {
                return .rejected("Stack names must not be empty.")
            }
            guard let index = stackIndex(stackID, in: document) else {
                return .rejected("The stack no longer exists.")
            }
            guard isUnique(trimmed, in: document.stacks, excluding: stackID) else {
                return .rejected("Stack names must be unique.")
            }
            guard document.stacks[index].name != trimmed else { return .noOp }
            document.stacks[index].name = trimmed

        case let .switchStack(stackID):
            guard stackIndex(stackID, in: document) != nil else {
                return .rejected("The stack no longer exists.")
            }
            guard document.currentStackID != stackID else { return .noOp }
            // The stack being left is the one a single switch should bring back.
            document.touchStack(document.currentStackID)
            document.currentStackID = stackID
            document.touchStack(stackID)

        case let .deleteStack(stackID):
            guard let index = stackIndex(stackID, in: document) else {
                return .rejected("The stack no longer exists.")
            }
            guard document.stacks.count > 1 else {
                return .rejected("The last stack cannot be deleted.")
            }
            document.stacks.remove(at: index)
            document.recentStackIDs.removeAll { $0 == stackID }
            if document.currentStackID == stackID {
                document.currentStackID = document.stacks[min(index, document.stacks.count - 1)].id
            }
            if document.lastCleared?.stackID == stackID {
                document.lastCleared = nil
            }

        case let .addNote(stackID, note):
            guard let stackIndex = stackIndex(stackID, in: document) else {
                return .rejected("The target stack no longer exists.")
            }
            guard !document.stacks[stackIndex].notes.contains(where: { $0.id == note.id }) else {
                return .rejected("The note already exists.")
            }
            document.stacks[stackIndex].notes.append(note)
            document.touchStack(stackID)

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

        case let .updateNoteProvenance(
            stackID,
            noteID,
            expectedApplication,
            provenance
        ):
            guard provenance.application == expectedApplication,
                  let stackIndex = stackIndex(stackID, in: document)
            else { return .noOp }

            if let noteIndex = document.stacks[stackIndex].notes.firstIndex(where: {
                $0.id == noteID
            }) {
                guard document.stacks[stackIndex].notes[noteIndex].provenance.application
                        == expectedApplication,
                      document.stacks[stackIndex].notes[noteIndex].provenance != provenance
                else { return .noOp }
                document.stacks[stackIndex].notes[noteIndex].provenance = provenance
            } else {
                guard document.lastCleared?.stackID == stackID,
                      let noteIndex = document.lastCleared?.notes.firstIndex(where: {
                          $0.id == noteID
                      }),
                      document.lastCleared?.notes[noteIndex].provenance.application
                        == expectedApplication,
                      document.lastCleared?.notes[noteIndex].provenance != provenance
                else { return .noOp }
                document.lastCleared?.notes[noteIndex].provenance = provenance
            }

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
            // Late provenance may enrich the same note. User edits and new notes
            // must survive cleanup of an older export snapshot.
            let removed = document.stacks[index].notes.filter { note in
                exported.contains { snapshot in
                    snapshot.id == note.id && snapshot.body == note.body
                        && snapshot.subject == note.subject && snapshot.createdAt == note.createdAt
                        && snapshot.provenance.application == note.provenance.application
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

    private static func isUnique(
        _ name: String,
        in stacks: [Stack],
        excluding excludedID: UUID? = nil
    ) -> Bool {
        guard let normalized = normalizedStackName(name) else { return false }
        return !stacks.contains {
            $0.id != excludedID && normalizedStackName($0.name) == normalized
        }
    }
}
