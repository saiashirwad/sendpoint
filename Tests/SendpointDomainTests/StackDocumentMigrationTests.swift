import Foundation
import XCTest
@testable import SendpointDomain

final class StackDocumentMigrationTests: XCTestCase {
    private let ids = (1...7).map { UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", $0))")! }

    func testFewerStacksKeepTheirNotesAndAreFilledToTheFixedCount() throws {
        let document = try migrate(stacks: [ids[0], ids[1]], current: ids[1], recent: [ids[1], ids[0]], notesIn: ids[0])

        XCTAssertEqual(document.version, StackDocument.currentVersion)
        XCTAssertEqual(document.stacks.count, StackDocument.stackCount)
        XCTAssertEqual(Array(document.stacks.map(\.id).prefix(2)), [ids[1], ids[0]])
        XCTAssertEqual(document.currentStackID, ids[1])
        XCTAssertEqual(document.stacks[1].notes.map(\.body), ["kept"])
        XCTAssertTrue(document.stacks[2...].allSatisfy(\.notes.isEmpty))
    }

    func testMoreStacksKeepTheCurrentThenTheMostRecentlyUsed() throws {
        let document = try migrate(
            stacks: ids, current: ids[6], recent: [ids[6], ids[3], ids[5]], notesIn: ids[3]
        )

        XCTAssertEqual(document.stacks.map(\.id), [ids[6], ids[3], ids[5], ids[0], ids[1]])
        XCTAssertEqual(document.currentStackID, ids[6])
        XCTAssertEqual(document.stacks[1].notes.map(\.body), ["kept"])
    }

    func testAnUndoBatchForADroppedStackIsDiscarded() throws {
        let kept = try migrate(stacks: ids, current: ids[0], recent: [], notesIn: ids[0], clearedIn: ids[1])
        XCTAssertEqual(kept.lastCleared?.stackID, ids[1])

        let dropped = try migrate(stacks: ids, current: ids[0], recent: [], notesIn: ids[0], clearedIn: ids[6])
        XCTAssertNil(dropped.lastCleared)
    }

    func testLiveLoadMigratesAndKeepsACopyOfTheOldFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = legacyJSON(stacks: [ids[0]], current: ids[0], recent: [ids[0]], notesIn: ids[0], clearedIn: nil)
        try data.write(to: directory.appendingPathComponent(StorePersistence.fileName))

        let loaded = try await StorePersistence.live(directory: directory).load()

        XCTAssertEqual(loaded?.stacks.count, StackDocument.stackCount)
        XCTAssertEqual(loaded?.stacks[0].notes.map(\.body), ["kept"])
        let backup = directory.appendingPathComponent("store.v3.json")
        XCTAssertEqual(try Data(contentsOf: backup), data)
        let persistence = StorePersistence.live(directory: directory)
        let reloaded = try await persistence.load()
        XCTAssertEqual(reloaded, loaded)
        let saved = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent(StorePersistence.fileName))
        ) as? [String: Any]
        XCTAssertEqual(saved?["version"] as? Int, StackDocument.currentVersion)
    }

    @MainActor
    func testStoreInitCanCaptureAndPreservesUndoAfterUpgradingFromVersion3() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = legacyJSON(stacks: [ids[0]], current: ids[0], recent: [], notesIn: ids[0], clearedIn: ids[0])
        try data.write(to: directory.appendingPathComponent(StorePersistence.fileName))

        let persistence = StorePersistence.live(directory: directory)
        let store = try await StackStore(persistence: persistence)
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.currentNotes.map(\.body), ["kept"])
        XCTAssertEqual(store.lastCleared?.notes.map(\.body), ["cleared"])

        let note = Note(subject: .standalone, body: "new voice note")
        store.mutate(.addNote(stackID: store.currentStackID, note: note))
        await store.drain(timeout: .seconds(2))
        XCTAssertNil(store.error)
        let saved = try await persistence.load()
        XCTAssertEqual(saved?.stacks[0].notes.map(\.body), ["kept", "new voice note"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("store.v3.json")), data)
        store.teardown()
    }

    func testBackupFailureLeavesTheLegacyFileUntouchedWithoutQuarantine() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        let data = legacyJSON(stacks: [ids[0]], current: ids[0], recent: [], notesIn: ids[0], clearedIn: nil)
        try data.write(to: file)
        // A dangling symlink reports no file, but cannot be replaced by copyItem.
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("store.v3.json"),
            withDestinationURL: directory.appendingPathComponent("missing")
        )

        do {
            _ = try await StorePersistence.live(directory: directory).load()
            XCTFail("Expected backup failure")
        } catch let error as StorePersistenceError {
            XCTAssertEqual(error, .unavailable)
        }

        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains(where: { $0.hasSuffix(".corrupt") }))
    }

    func testRetryDoesNotOverwriteAnExistingLegacyBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = legacyJSON(stacks: [ids[0]], current: ids[0], recent: [], notesIn: ids[0], clearedIn: nil)
        try data.write(to: directory.appendingPathComponent(StorePersistence.fileName))
        let backup = directory.appendingPathComponent("store.v3.json")
        let earlierBackup = Data("original backup".utf8)
        try earlierBackup.write(to: backup)

        let loaded = try await StorePersistence.live(directory: directory).load()

        XCTAssertEqual(loaded?.stacks[0].notes.map(\.body), ["kept"])
        XCTAssertEqual(try Data(contentsOf: backup), earlierBackup)
    }

    func testMalformedVersion3IsQuarantinedWithOriginalBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(#"{"version":3,"stacks":"invalid"}"#.utf8)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        try data.write(to: file)

        let loaded = try await StorePersistence.live(directory: directory).load()

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = try XCTUnwrap(names.first(where: { $0.hasSuffix(".corrupt") }))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(quarantined)), data)
    }

    private func migrate(
        stacks: [UUID], current: UUID, recent: [UUID], notesIn: UUID, clearedIn: UUID? = nil
    ) throws -> StackDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try StackDocumentMigration.migrate(
            legacy: legacyJSON(stacks: stacks, current: current, recent: recent, notesIn: notesIn, clearedIn: clearedIn),
            decoder: decoder
        )
    }

    private func legacyJSON(
        stacks: [UUID], current: UUID, recent: [UUID], notesIn: UUID, clearedIn: UUID?
    ) -> Data {
        func note(_ body: String) -> [String: Any] {
            ["id": UUID().uuidString, "subject": ["standalone": [String: Any]()], "body": body,
             "createdAt": "2023-11-14T22:13:20Z"]
        }
        var root: [String: Any] = [
            "version": 3,
            "currentStackID": current.uuidString,
            "recentStackIDs": recent.map(\.uuidString),
            "stacks": stacks.enumerated().map { index, id in
                ["id": id.uuidString, "name": "Stack \(index)", "createdAt": "2023-11-14T22:13:20Z",
                 "notes": id == notesIn ? [note("kept")] : []] as [String: Any]
            },
        ]
        if let clearedIn {
            root["lastCleared"] = ["stackID": clearedIn.uuidString, "notes": [note("cleared")]]
        }
        return try! JSONSerialization.data(withJSONObject: root)
    }
}
