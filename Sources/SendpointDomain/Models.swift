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
    public var name: String
    public var notes: [Note]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        notes: [Note] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
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
    public static let currentVersion = 3

    public var version: Int
    public var stacks: [Stack]
    public var currentStackID: UUID
    public var lastCleared: ClearedBatch?
    /// Stacks in the order they were last made current or written to,
    /// most recent first.
    public var recentStackIDs: [UUID]

    public init(
        version: Int = StackDocument.currentVersion,
        stacks: [Stack],
        currentStackID: UUID,
        lastCleared: ClearedBatch? = nil,
        recentStackIDs: [UUID] = []
    ) {
        self.version = version
        self.stacks = stacks
        self.currentStackID = currentStackID
        self.lastCleared = lastCleared
        self.recentStackIDs = recentStackIDs
    }

    /// Every stack, the current one first, then the rest by how recently
    /// they were used, then any never-used stacks in list order. This is the
    /// order a ⌘Tab-style switcher cycles through: one step always reaches
    /// the stack used just before this one.
    public var stacksByRecency: [Stack] {
        var seen: Set<UUID> = [currentStackID]
        var ordered: [Stack] = stacks.filter { $0.id == currentStackID }
        for id in recentStackIDs where !seen.contains(id) {
            guard let stack = stacks.stack(id: id) else { continue }
            seen.insert(id)
            ordered.append(stack)
        }
        ordered += stacks.filter { !seen.contains($0.id) }
        return ordered
    }

    /// Moves a stack to the front of the recency list.
    mutating func touchStack(_ id: UUID) {
        recentStackIDs.removeAll { $0 == id }
        recentStackIDs.insert(id, at: 0)
    }
}

public extension Array where Element == Stack {
    func stack(id: UUID) -> Stack? {
        first { $0.id == id }
    }
}
