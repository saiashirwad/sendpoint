import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StackPaletteControllerTests: XCTestCase {
    func testPaletteRetriesAWriteQueuedByAnotherOwner() async throws {
        let document = StackDocument.empty()
        let disk = PaletteRetryDisk()
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { try await disk.commit($0) }
        ))
        defer { store.teardown() }
        let note = Note(subject: .standalone, body: "Captured elsewhere")
        store.mutate(.addNote(stackID: store.currentStackID, note: note))
        await store.waitForIdle()
        XCTAssertEqual(store.state, .halted)
        XCTAssertTrue(store.hasPendingMutations)

        let suite = "StackPaletteControllerTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let export = ExportController(services: ExportServices(
            write: { _ in XCTFail("Retry must not copy"); return nil },
            paste: { _, _ in XCTFail("Retry must not paste"); return false }
        ))
        defer { export.teardown() }
        let palette = StackPaletteController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults), export: export,
            onSelectTemplate: { _ in XCTFail("Retry must not change templates") }
        )
        defer { palette.send(.teardown) }
        palette.send(.open)
        XCTAssertNil(palette.projection.problem)
        palette.send(.retryPendingStoreChanges)
        await store.waitForIdle()

        XCTAssertEqual(store.currentNotes, [note])
        XCTAssertFalse(store.hasPendingMutations)
        XCTAssertNil(store.error)
        XCTAssertFalse(palette.state.isBusy)
        let attempts = await disk.attempts
        XCTAssertEqual(attempts, 2)
    }
}

private actor PaletteRetryDisk {
    var attempts = 0

    func commit(_ document: StackDocument) throws {
        attempts += 1
        if attempts == 1 { throw StorePersistenceError.unavailable }
    }
}
