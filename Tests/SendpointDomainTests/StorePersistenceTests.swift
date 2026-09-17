import Foundation
import XCTest
@testable import SendpointDomain

final class StorePersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let stackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    func testLiveRoundTripUsesVersionedStoreJSON() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = StorePersistence.live(directory: directory)
        let first = document(name: "Round trip").stacks[0]
        let second = Stack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            name: "Second",
            createdAt: now
        )
        let expected = StackDocument(
            stacks: [first, second],
            currentStackID: second.id
        )

        try await persistence.commit(expected)

        let loaded = try await persistence.load()
        XCTAssertEqual(loaded, expected)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(StorePersistence.fileName).path
            )
        )
    }

    func testMalformedCurrentVersionIsQuarantined() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        try Data(#"{"version":\#(StackDocument.currentVersion)}"#.utf8).write(to: file)
        let fixedNow = now
        let persistence = StorePersistence.live(directory: directory, now: { fixedNow })

        let recovered = try await persistence.load()
        XCTAssertNil(recovered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains(where: { $0.hasSuffix(".corrupt") }))
    }

    func testUnsupportedVersionsAreRejectedWithoutQuarantine() async throws {
        for version in [StackDocument.currentVersion - 1, StackDocument.currentVersion + 1] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(StorePersistence.fileName)
            try Data(#"{"version":\#(version)}"#.utf8).write(to: file)

            do {
                _ = try await StorePersistence.live(directory: directory).load()
                XCTFail("Expected unsupported version")
            } catch let error as StorePersistenceError {
                XCTAssertEqual(error, .unsupportedVersion(version))
            }

            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertFalse(names.contains(where: { $0.hasSuffix(".corrupt") }))
        }
    }

    func testInvalidCommitDoesNotReplaceLastCommittedDocument() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = StorePersistence.live(directory: directory)
        let original = document()
        try await persistence.commit(original)
        let invalid = StackDocument(
            stacks: original.stacks,
            currentStackID: UUID()
        )

        do {
            try await persistence.commit(invalid)
            XCTFail("Expected invalid document")
        } catch let error as StorePersistenceError {
            guard case .invalidDocument = error else {
                return XCTFail("Expected invalid document, got \(error)")
            }
        }

        let loaded = try await persistence.load()
        XCTAssertEqual(loaded, original)
    }

    func testMissingFileLoadsNilWithoutQuarantine() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = StorePersistence.live(directory: directory)

        let loaded = try await persistence.load()

        XCTAssertNil(loaded)
        let didQuarantine = await persistence.didQuarantineCorruptFile()
        XCTAssertFalse(didQuarantine)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(StorePersistence.fileName).path
            )
        )
    }

    func testUnreadableFileThrowsUnavailableWithoutQuarantine() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A directory where store.json belongs makes Data(contentsOf:) throw
        // a raw I/O error: the deterministic stand-in for unreadable storage.
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let persistence = StorePersistence.live(directory: directory)

        do {
            _ = try await persistence.load()
            XCTFail("Expected unavailable storage")
        } catch let error as StorePersistenceError {
            XCTAssertEqual(error, .unavailable)
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains(where: { $0.hasSuffix(".corrupt") }))
        let didQuarantine = await persistence.didQuarantineCorruptFile()
        XCTAssertFalse(didQuarantine)
    }

    func testNonJSONEnvelopeFailureIsQuarantinedWithOriginalBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        let corrupt = Data("not json at all{{{".utf8)
        try corrupt.write(to: file)
        let fixedNow = now
        let persistence = StorePersistence.live(directory: directory, now: { fixedNow })

        let recovered = try await persistence.load()

        XCTAssertNil(recovered)
        let didQuarantine = await persistence.didQuarantineCorruptFile()
        XCTAssertTrue(didQuarantine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = names.filter { $0.hasSuffix(".corrupt") }
        XCTAssertEqual(quarantined.count, 1)
        let preserved = try Data(contentsOf: directory.appendingPathComponent(quarantined[0]))
        XCTAssertEqual(preserved, corrupt)
    }

    func testInvalidDocumentIsQuarantinedWithOriginalBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let invalid = try encoder.encode(
            StackDocument(stacks: [], currentStackID: UUID())
        )
        try invalid.write(to: file)
        let fixedNow = now
        let persistence = StorePersistence.live(directory: directory, now: { fixedNow })

        let recovered = try await persistence.load()

        XCTAssertNil(recovered)
        let didQuarantine = await persistence.didQuarantineCorruptFile()
        XCTAssertTrue(didQuarantine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = names.filter { $0.hasSuffix(".corrupt") }
        XCTAssertEqual(quarantined.count, 1)
        let preserved = try Data(contentsOf: directory.appendingPathComponent(quarantined[0]))
        XCTAssertEqual(preserved, invalid)
    }

    @MainActor
    func testStoreInitPropagatesUnavailableWithoutCommittingFreshDefault() async throws {
        let recorder = PersistenceCommitRecorder()
        let persistence = StorePersistence(
            load: { throw StorePersistenceError.unavailable },
            commit: { document in await recorder.record(document) }
        )

        do {
            _ = try await StackStore(persistence: persistence)
            XCTFail("Expected unavailable storage")
        } catch let error as StorePersistenceError {
            XCTAssertEqual(error, .unavailable)
        }

        let commits = await recorder.documents()
        XCTAssertEqual(commits, [])
    }

    @MainActor
    func testLiveIOErrorPropagatesThroughStoreInitWithoutWipe() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(StorePersistence.fileName)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        do {
            _ = try await StackStore(persistence: .live(directory: directory))
            XCTFail("Expected unavailable storage")
        } catch let error as StorePersistenceError {
            XCTAssertEqual(error, .unavailable)
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
        // Still a directory: init threw before committing a fresh Default,
        // which would have failed (or replaced the entry with a file).
        XCTAssertTrue(isDirectory.boolValue)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains(where: { $0.hasSuffix(".corrupt") }))
    }

    @MainActor
    func testStoreInitFlagsQuarantineButNotFirstLaunch() async throws {
        let corruptDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: corruptDirectory) }
        try FileManager.default.createDirectory(
            at: corruptDirectory,
            withIntermediateDirectories: true
        )
        try Data("not json at all{{{".utf8).write(
            to: corruptDirectory.appendingPathComponent(StorePersistence.fileName)
        )
        let fixedNow = now

        let quarantinedStore = try await StackStore(
            persistence: .live(directory: corruptDirectory, now: { fixedNow })
        )

        XCTAssertTrue(quarantinedStore.didQuarantineCorruptFile)
        XCTAssertEqual(quarantinedStore.currentStack.name, "Default")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: corruptDirectory.appendingPathComponent(StorePersistence.fileName).path
            )
        )

        let freshDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: freshDirectory) }
        let freshStore = try await StackStore(
            persistence: .live(directory: freshDirectory)
        )

        XCTAssertFalse(freshStore.didQuarantineCorruptFile)
        XCTAssertEqual(freshStore.currentStack.name, "Default")
    }

    private func document(name: String = "First") -> StackDocument {
        StackDocument(
            stacks: [Stack(id: stackID, name: name, createdAt: now)],
            currentStackID: stackID
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private actor PersistenceCommitRecorder {
    private var committed: [StackDocument] = []

    func record(_ document: StackDocument) {
        committed.append(document)
    }

    func documents() -> [StackDocument] {
        committed
    }
}
