import Foundation

public struct ApplicationIdentity: Codable, Hashable, Sendable {
    public var name: String
    public var bundleID: String?

    public init(name: String, bundleID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
    }
}

public enum Subject: Codable, Hashable, Sendable {
    case selection(quote: String)
    case standalone
}

public struct Provenance: Codable, Hashable, Sendable {
    public var application: ApplicationIdentity
    public var windowTitle: String?
    public var url: URL?
    public var workingDirectory: URL?

    public init(
        application: ApplicationIdentity,
        windowTitle: String? = nil,
        url: URL? = nil,
        workingDirectory: URL? = nil
    ) {
        self.application = application
        self.windowTitle = windowTitle
        self.url = url
        self.workingDirectory = workingDirectory
    }
}

public struct Annotation: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var subject: Subject
    public var note: String
    public var provenance: Provenance
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        subject: Subject,
        note: String,
        provenance: Provenance,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.note = note
        self.provenance = provenance
        self.createdAt = createdAt
    }
}

public struct Session: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var entries: [Annotation]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        entries: [Annotation] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
    }
}

public struct ClearedBatch: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var entries: [Annotation]

    public init(sessionID: UUID, entries: [Annotation]) {
        self.sessionID = sessionID
        self.entries = entries
    }
}

public struct StoreDocument: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var sessions: [Session]
    public var currentSessionID: UUID
    public var lastCleared: ClearedBatch?
    /// Sessions in the order they were last made current or written to,
    /// most recent first. Documents written before this field existed
    /// decode with an empty list, which `sessionsByRecency` tolerates.
    public var recentSessionIDs: [UUID]

    public init(
        version: Int = StoreDocument.currentVersion,
        sessions: [Session],
        currentSessionID: UUID,
        lastCleared: ClearedBatch? = nil,
        recentSessionIDs: [UUID] = []
    ) {
        self.version = version
        self.sessions = sessions
        self.currentSessionID = currentSessionID
        self.lastCleared = lastCleared
        self.recentSessionIDs = recentSessionIDs
    }

    private enum CodingKeys: String, CodingKey {
        case version, sessions, currentSessionID, lastCleared, recentSessionIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sessions = try container.decode([Session].self, forKey: .sessions)
        currentSessionID = try container.decode(UUID.self, forKey: .currentSessionID)
        lastCleared = try container.decodeIfPresent(ClearedBatch.self, forKey: .lastCleared)
        recentSessionIDs = try container.decodeIfPresent([UUID].self, forKey: .recentSessionIDs) ?? []
    }

    /// Every session, the current one first, then the rest by how recently
    /// they were used, then any never-used sessions in list order. This is the
    /// order a ⌘Tab-style switcher cycles through: one step always reaches
    /// the stack used just before this one.
    public var sessionsByRecency: [Session] {
        var seen: Set<UUID> = [currentSessionID]
        var ordered: [Session] = sessions.filter { $0.id == currentSessionID }
        for id in recentSessionIDs where !seen.contains(id) {
            guard let session = sessions.first(where: { $0.id == id }) else { continue }
            seen.insert(id)
            ordered.append(session)
        }
        ordered += sessions.filter { !seen.contains($0.id) }
        return ordered
    }

    /// Moves a session to the front of the recency list.
    mutating func touchSession(_ id: UUID) {
        recentSessionIDs.removeAll { $0 == id }
        recentSessionIDs.insert(id, at: 0)
    }
}
