import Foundation

public enum Subject: Codable, Hashable, Sendable {
    case selection(quote: String)
    case standalone
}

public struct Note: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var subject: Subject
    public var body: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        subject: Subject,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.body = body
        self.createdAt = createdAt
    }
}

public struct Stack: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var notes: [Note]

    public init(id: UUID = UUID(), notes: [Note] = []) {
        self.id = id
        self.notes = notes
    }

    public var startedAt: Date? {
        notes.map(\.createdAt).min()
    }
}

public struct ClearedBatch: Codable, Hashable, Sendable {
    public var stackID: UUID
    public var notes: [Note]

    public init(stackID: UUID, notes: [Note]) {
        self.stackID = stackID
        self.notes = notes
    }
}

public struct StackDocument: Codable, Hashable, Sendable {
    public static let currentVersion = 4
    public static let stackCount = 5

    public var version: Int
    public var stacks: [Stack]
    public var currentStackID: UUID
    public var lastCleared: ClearedBatch?

    public init(
        version: Int = StackDocument.currentVersion,
        stacks: [Stack],
        currentStackID: UUID,
        lastCleared: ClearedBatch? = nil
    ) {
        self.version = version
        self.stacks = stacks
        self.currentStackID = currentStackID
        self.lastCleared = lastCleared
    }

    public static func empty() -> StackDocument {
        let stacks = (0..<stackCount).map { _ in Stack() }
        return StackDocument(stacks: stacks, currentStackID: stacks[0].id)
    }
}

public extension Array where Element == Stack {
    func stack(id: UUID) -> Stack? {
        first { $0.id == id }
    }

    func number(of id: UUID) -> Int? {
        firstIndex { $0.id == id }.map { $0 + 1 }
    }

    func stack(number: Int) -> Stack? {
        indices.contains(number - 1) ? self[number - 1] : nil
    }
}
