import Foundation

public struct DiagnosticRecord: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable { case capture, save, export, clipboard, paste, cleanup, load }
    public enum Outcome: String, Codable, Sendable {
        case accepted, rejected, succeeded, failed, cancelled, retry, missing, quarantined, unsupported
    }

    public let stage: Stage
    public let outcome: Outcome
    public let operationID: UUID?
    public let stackID: UUID?
    public let noteID: UUID?

    public init(_ stage: Stage, _ outcome: Outcome, operationID: UUID? = nil,
                stackID: UUID? = nil, noteID: UUID? = nil) {
        self.stage = stage
        self.outcome = outcome
        self.operationID = operationID
        self.stackID = stackID
        self.noteID = noteID
    }
}

public typealias DiagnosticSink = @Sendable (DiagnosticRecord) -> Void

public extension StackMutationOutcome {
    var diagnosticOutcome: DiagnosticRecord.Outcome {
        switch self {
        case .committed, .noOp: .succeeded
        case .rejected: .rejected
        case .commitFailed: .failed
        case .cancelled: .cancelled
        }
    }
}

public final class DiagnosticJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let file: URL
    private let maxBytes: Int

    public init(file: URL, maxBytes: Int = 2_000_000) {
        precondition(maxBytes >= 512)
        self.file = file
        self.maxBytes = maxBytes
    }

    public func record(_ record: DiagnosticRecord) {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)
        guard data.count <= maxBytes else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let previous = file.appendingPathExtension("1")
            let previousSize = (try? manager.attributesOfItem(atPath: previous.path)[.size] as? Int) ?? 0
            if previousSize > maxBytes { try manager.removeItem(at: previous) }
            let size = (try? manager.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            if size + data.count > maxBytes {
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                if size > maxBytes {
                    try manager.removeItem(at: file)
                } else {
                    try manager.moveItem(at: file, to: previous)
                }
            }
            if manager.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
            }
        } catch {
        }
    }
}
