import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class PaletteSelectionTests: XCTestCase {
    func testNavigationDiscardsDeferredClearAndCopyIncludingAwayAndBack() async throws {
        for action in [PaletteAction.clearStack, .copyStack] {
            for navigation in [[StackSlot.two], [.two, .one]] {
                let fixture = try await deferredFixture()
                defer { fixture.teardown() }
                fixture.edit()
                fixture.controller.send(.perform(action))
                await fixture.disk.waitForEntry()
                for slot in navigation { fixture.store.select(slot) }
                await fixture.disk.release()
                await fixture.store.waitForIdle()

                XCTAssertEqual(fixture.store.currentStackID, navigation.last)
                XCTAssertEqual(fixture.store.stack(id: .one).notes.map(\.body), ["Updated source draft"])
                XCTAssertEqual(fixture.store.stack(id: .two).notes, [fixture.other])
                XCTAssertNil(fixture.store.lastCleared)
                XCTAssertEqual(fixture.boundary.snapshot.slots, [])
                XCTAssertEqual(fixture.boundary.snapshot.copies, [])
                XCTAssertFalse(fixture.controller.state.isBusy)
            }
        }
    }

    func testLocalNavigationDiscardsADeferredCommandBeforeItsSelectionEffect() async throws {
        let fixture = try await deferredFixture()
        defer { fixture.teardown() }
        fixture.edit()
        fixture.controller.send(.perform(.clearStack))
        await fixture.disk.waitForEntry()
        fixture.controller.send(.selectStack(2))
        fixture.controller.send(.selectStack(1))
        await fixture.disk.release()
        await fixture.store.waitForIdle()
        XCTAssertEqual(fixture.store.stack(id: .one).notes.map(\.body), ["Updated source draft"])
        XCTAssertEqual(fixture.store.stack(id: .two).notes, [fixture.other])
        XCTAssertNil(fixture.store.lastCleared)
    }

    func testDeferredClearAndCopyStillRunAfterSaveWithoutNavigation() async throws {
        for action in [PaletteAction.clearStack, .copyStack] {
            let fixture = try await deferredFixture()
            defer { fixture.teardown() }
            fixture.edit()
            fixture.controller.send(.perform(action))
            await fixture.disk.waitForEntry()
            XCTAssertEqual(fixture.store.stack(id: .one).notes, [fixture.source])
            XCTAssertEqual(fixture.boundary.snapshot.copies, [])
            await fixture.disk.release()
            await fixture.store.waitForIdle()

            XCTAssertEqual(fixture.store.currentStackID, .one)
            XCTAssertEqual(fixture.store.stack(id: .one).notes, [])
            XCTAssertEqual(fixture.store.lastCleared?.stackID, .one)
            XCTAssertEqual(fixture.store.lastCleared?.notes.map(\.body), ["Updated source draft"])
            XCTAssertEqual(fixture.store.stack(id: .two).notes, [fixture.other])
            if action == .copyStack {
                XCTAssertEqual(fixture.boundary.snapshot.slots, [.one])
                XCTAssertEqual(fixture.boundary.snapshot.copies.count, 1)
                XCTAssertTrue(fixture.boundary.snapshot.copies[0].contains("Updated source draft"))
                XCTAssertFalse(fixture.boundary.snapshot.copies[0].contains(fixture.other.body))
            } else {
                XCTAssertEqual(fixture.boundary.snapshot.slots, [])
                XCTAssertEqual(fixture.boundary.snapshot.copies, [])
            }
        }
    }

    func testPendingWindowCloseSurvivesNavigationWhileTheOriginalDraftSaves() async throws {
        for navigation in [[], [StackSlot.two], [.two, .one]] {
            let fixture = try await deferredFixture()
            defer { fixture.teardown() }
            fixture.edit()
            fixture.controller.send(.close)
            await fixture.disk.waitForEntry()
            XCTAssertEqual(fixture.boundary.snapshot.closes, 0)
            for slot in navigation { fixture.store.select(slot) }
            await fixture.disk.release()
            await fixture.store.waitForIdle()
            XCTAssertEqual(fixture.controller.state.lifecycle, .closed)
            XCTAssertEqual(fixture.boundary.snapshot.closes, 1)
            XCTAssertEqual(fixture.store.stack(id: .one).notes.map(\.body), ["Updated source draft"])
            XCTAssertEqual(fixture.store.stack(id: .two).notes, [fixture.other])
            XCTAssertEqual(fixture.boundary.snapshot.slots, [])
        }
    }

    private func deferredFixture() async throws -> DeferredFixture {
        let suite = "PaletteSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let source = Note(subject: .standalone, body: "Original source")
        let other = Note(subject: .standalone, body: "Other stack must stay intact")
        let document = StackDocument(stacks: filled([Stack(notes: [source]), Stack(notes: [other])]))
        let disk = SuspendedPaletteCommit()
        let observer = PaletteChangeObserver()
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in await disk.commit() }
        ), onChange: { observer.controller?.send(.documentChanged) })
        let boundary = PaletteBoundaryRecorder()
        let export = ExportController(services: ExportServices(
            write: { boundary.copy($0) }, paste: { _, _ in false }
        ), diagnostics: { boundary.record($0) })
        let controller = StackPaletteController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults), export: export,
            onSelectTemplate: { _ in }
        )
        observer.controller = controller
        controller.onClose = { boundary.close() }
        return DeferredFixture(store: store, controller: controller, export: export,
                               disk: disk, boundary: boundary, source: source, other: other,
                               defaults: defaults, suite: suite)
    }

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
        guard !entered else { return }
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

@MainActor
private final class PaletteChangeObserver {
    weak var controller: StackPaletteController?
}

@MainActor
private struct DeferredFixture {
    let store: StackStore
    let controller: StackPaletteController
    let export: ExportController
    let disk: SuspendedPaletteCommit
    let boundary: PaletteBoundaryRecorder
    let source: Note
    let other: Note
    let defaults: UserDefaults
    let suite: String

    func edit() {
        controller.send(.open)
        controller.send(.perform(.editNote(source.id)))
        controller.send(.editText("Updated source draft"))
    }

    func teardown() {
        controller.send(.teardown)
        export.teardown()
        store.teardown()
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class PaletteBoundaryRecorder: @unchecked Sendable {
    struct Snapshot {
        var slots: [StackSlot] = []
        var copies: [String] = []
        var closes = 0
    }
    private let lock = NSLock()
    private var value = Snapshot()

    var snapshot: Snapshot { lock.withLock { value } }

    func record(_ record: DiagnosticRecord) {
        guard record.stage == .export, record.outcome == .accepted,
              record.noteID == nil, let slot = record.stackID else { return }
        lock.withLock { value.slots.append(slot) }
    }

    func copy(_ text: String) -> Int? {
        lock.withLock { value.copies.append(text); return value.copies.count }
    }

    func close() { lock.withLock { value.closes += 1 } }
}
