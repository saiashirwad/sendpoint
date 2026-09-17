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
