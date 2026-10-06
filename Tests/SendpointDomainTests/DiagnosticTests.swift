import Foundation
import XCTest
@testable import SendpointDomain

final class DiagnosticTests: XCTestCase {
    func testJournalRotatesDuringOneRunAndContainsOnlyTypedMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("diagnostics.jsonl")
        let journal = DiagnosticJournal(file: file, maxBytes: 512)
        let id = UUID()
        for _ in 0..<100 {
            journal.record(DiagnosticRecord(.save, .succeeded, operationID: id, stackID: .one, noteID: id))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(names), ["diagnostics.jsonl", "diagnostics.jsonl.1"])
        for name in names {
            let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertLessThanOrEqual(bytes.count, 512)
            for line in bytes.split(separator: 0x0A) {
                let record = try JSONDecoder().decode(DiagnosticRecord.self, from: Data(line))
                XCTAssertEqual(record.noteID, id)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
                XCTAssertEqual(Set(object.keys), ["stage", "outcome", "operationID", "stackID", "noteID"])
            }
        }
    }

    func testJournalDiscardsOversizedPriorDiagnosticFilesBeforeAppending() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("diagnostics.jsonl")
        try Data(repeating: 0x61, count: 1024).write(to: file)
        try Data(repeating: 0x62, count: 1024).write(to: file.appendingPathExtension("1"))
        DiagnosticJournal(file: file, maxBytes: 512).record(DiagnosticRecord(.load, .missing))
        let bytes = try Data(contentsOf: file)
        XCTAssertLessThanOrEqual(bytes.count, 512)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticRecord.self, from: bytes), DiagnosticRecord(.load, .missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("1").path))
    }

    func testMissingAndQuarantinedLoadsHaveDistinctRecordsWithoutContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = DiagnosticRecorder()
        let persistence = StorePersistence.live(directory: directory, diagnostics: records.record)
        let missing = try await persistence.load()
        XCTAssertNil(missing)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let secret = "PRIVATE NOTE CONTENT https://private.example/"
        try Data(secret.utf8).write(to: directory.appendingPathComponent(StorePersistence.fileName))
        let corrupt = try await persistence.load()
        XCTAssertNil(corrupt)
        XCTAssertEqual(records.values, [DiagnosticRecord(.load, .missing), DiagnosticRecord(.load, .quarantined)])
        let encoded = try JSONEncoder().encode(records.values)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(secret))
    }

    @MainActor
    func testSaveAndCleanupShareExplicitOperationAndNoteIdentity() async throws {
        let document = StackDocument()
        let records = DiagnosticRecorder()
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }),
                                        diagnostics: records.record)
        defer { store.teardown() }
        let note = Note(subject: .standalone, body: "private")
        let exportID = UUID()
        store.mutate(.addNote(stackID: store.currentStackID, note: note), operationID: note.id)
        await store.waitForIdle()
        store.mutate(.clearExportedNotes(stackID: store.currentStackID, notes: [note]), operationID: exportID)
        await store.waitForIdle()
        XCTAssertEqual(records.values.map(\.outcome), [.accepted, .succeeded, .accepted, .succeeded])
        XCTAssertEqual(records.values.map(\.noteID), Array(repeating: note.id, count: 4))
        XCTAssertEqual(records.values.map(\.operationID), [note.id, note.id, exportID, exportID])
    }
}

private final class DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [DiagnosticRecord] = []
    var values: [DiagnosticRecord] {
        lock.lock(); defer { lock.unlock() }
        return records
    }
    func record(_ record: DiagnosticRecord) {
        lock.lock(); defer { lock.unlock() }
        records.append(record)
    }
}
