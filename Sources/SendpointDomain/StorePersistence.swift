import Foundation

public enum StorePersistenceError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            "This notes file uses an unsupported format."
        case .unavailable:
            "Notes storage is unavailable."
        }
    }
}

public struct StorePersistence: Sendable {
    public static let fileName = "slots.json"
    public static let currentVersion = 1

    private let loadOperation: @Sendable () async throws -> StackDocument?
    private let commitOperation: @Sendable (StackDocument) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> StackDocument?,
        commit: @escaping @Sendable (StackDocument) async throws -> Void
    ) {
        self.loadOperation = load
        self.commitOperation = commit
    }

    public func load() async throws -> StackDocument? {
        try await loadOperation()
    }

    public func commit(_ document: StackDocument) async throws {
        try await commitOperation(document)
    }

    public static let unavailable = StorePersistence(
        load: { throw StorePersistenceError.unavailable },
        commit: { _ in throw StorePersistenceError.unavailable }
    )

    public static func live(
        directory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        diagnostics: @escaping DiagnosticSink = { _ in }
    ) -> StorePersistence {
        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Sendpoint", isDirectory: true)
        let storage = AtomicJSONStore(directory: baseDirectory, now: now, diagnostics: diagnostics)
        return StorePersistence(
            load: { try await storage.load() },
            commit: { try await storage.commit($0) }
        )
    }
}

private actor AtomicJSONStore {
    private struct DiskEnvelope: Codable {
        let version: Int
        let document: StackDocument
    }

    private struct VersionEnvelope: Decodable {
        var version: Int
    }

    private let directory: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date
    private let diagnostics: DiagnosticSink
    private let quarantineDateFormatter: ISO8601DateFormatter

    init(directory: URL, now: @escaping @Sendable () -> Date, diagnostics: @escaping DiagnosticSink) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(StorePersistence.fileName)
        self.now = now
        self.diagnostics = diagnostics

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.quarantineDateFormatter = ISO8601DateFormatter()
    }

    func load() throws -> StackDocument? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            diagnostics(DiagnosticRecord(.load, .missing))
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let code = (error as NSError).code
            if (error as NSError).domain == NSCocoaErrorDomain,
               code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError
            {
                diagnostics(DiagnosticRecord(.load, .missing))
                return nil
            }
            diagnostics(DiagnosticRecord(.load, .failed))
            throw StorePersistenceError.unavailable
        }

        let version: Int
        do {
            version = try decoder.decode(VersionEnvelope.self, from: data).version
        } catch {
            try quarantine(using: fileManager)
            return nil
        }
        guard version == StorePersistence.currentVersion else {
            diagnostics(DiagnosticRecord(.load, .unsupported))
            throw StorePersistenceError.unsupportedVersion(version)
        }

        do {
            let document = try decoder.decode(DiskEnvelope.self, from: data).document
            diagnostics(DiagnosticRecord(.load, .succeeded))
            return document
        } catch {
            try quarantine(using: fileManager)
            return nil
        }
    }

    func commit(_ document: StackDocument) throws {
        let data = try encoder.encode(DiskEnvelope(version: StorePersistence.currentVersion, document: document))
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func quarantine(using fileManager: FileManager) throws {
        let stamp = quarantineDateFormatter
            .string(from: now())
            .replacingOccurrences(of: ":", with: "-")
        var destination = fileURL.appendingPathExtension("\(stamp).corrupt")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = fileURL.appendingPathExtension("\(stamp)-\(suffix).corrupt")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
        } catch {
            diagnostics(DiagnosticRecord(.load, .failed))
            throw StorePersistenceError.unavailable
        }
        diagnostics(DiagnosticRecord(.load, .quarantined))
    }
}
