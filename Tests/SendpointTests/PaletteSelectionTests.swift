import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class PaletteSelectionTests: XCTestCase {
    func testImmediateNavigationKeepsTheEditSourceAndDoesNotReplayAfterANewerSelection() async throws {
        let suite = "PaletteSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let note = Note(subject: .standalone, body: "Original")
        let document = StackDocument(stacks: filled([Stack(notes: [note])]))
        let disk = SuspendedPaletteCommit()
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in await disk.commit() }
        ))
        let controller = StackPaletteController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults),
            export: ExportController(services: ExportServices(write: { _ in nil }, paste: { _, _ in false })),
            onSelectTemplate: { _ in }
        )
        defer { controller.send(.teardown); store.teardown() }
        controller.send(.open)
        controller.send(.perform(.editNote(note.id)))
        controller.send(.editText("Updated in its original slot"))
        controller.send(.selectStack(2))
        XCTAssertEqual(store.currentStackID, .two)
        XCTAssertTrue(controller.state.isBusy)
        controller.send(.documentChanged)
        await disk.waitForEntry()
        XCTAssertEqual(store.stack(id: .one).notes, [note])
        controller.send(.key(.commandDigit(3), textHasSelection: false))
        XCTAssertEqual(store.currentStackID, .three)
        controller.send(.documentChanged)
        store.select(.five)
        controller.send(.documentChanged)
        XCTAssertEqual(controller.projection.facts.current?.id, .five)
        await disk.release()
        await store.waitForIdle()
        XCTAssertEqual(store.currentStackID, .five)
        XCTAssertEqual(store.stack(id: .one).notes.map(\.body), ["Updated in its original slot"])
        XCTAssertEqual(store.stack(id: .two).notes, [])
        XCTAssertFalse(controller.state.isBusy)
        XCTAssertEqual(controller.projection.facts.current?.id, .five)
    }
}

private actor SuspendedPaletteCommit {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var commitWaiter: CheckedContinuation<Void, Never>?

    func commit() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { commitWaiter = $0 }
    }

    func waitForEntry() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        commitWaiter?.resume()
        commitWaiter = nil
    }
}
