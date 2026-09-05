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

    public init(
        version: Int = StoreDocument.currentVersion,
        sessions: [Session],
        currentSessionID: UUID,
        lastCleared: ClearedBatch? = nil
    ) {
        self.version = version
        self.sessions = sessions
        self.currentSessionID = currentSessionID
        self.lastCleared = lastCleared
    }
}
