import Foundation
import SendpointDomain

nonisolated enum Diag {
    static let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sendpoint/diagnostics.jsonl")
    private static let journal = DiagnosticJournal(file: fileURL)

    static func record(_ record: DiagnosticRecord) {
        journal.record(record)
    }
}
