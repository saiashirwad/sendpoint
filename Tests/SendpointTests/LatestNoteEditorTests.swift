import AppKit
import Carbon.HIToolbox
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class LatestNoteEditorTests: XCTestCase {
    func testLatestUsesRecordingTimeAndSavePreservesIdentityAndContextAfterStackSwitch() async throws {
        let latest = Note(subject: .selection(quote: "Original passage"), body: "Newest recording",
                          createdAt: Date(timeIntervalSince1970: 300))
        let older = Note(subject: .standalone, body: "Reordered older note", createdAt: Date(timeIntervalSince1970: 100))
        let fixture = try await makeStore(notes: [latest, older])
        let store = fixture.store
        defer { store.teardown() }
        let model = LatestNoteEditor(store: store)
        model.send(.open)
        XCTAssertEqual(model.state.draft?.original, latest)
        let firstStack = store.currentStackID
        model.text = "Corrected transcription"
        let session = model.state.draft?.sessionID
        store.mutate(.switchStack(stackID: store.stacks[1].id))
        await store.waitForIdle()
        model.send(.open)
        XCTAssertEqual(model.state.draft?.sessionID, session)
        XCTAssertEqual(model.text, "Corrected transcription")
        model.send(.save)
        XCTAssertTrue(model.hasPendingSave)
        model.text = "Late keystroke"
        model.send(.dismiss)
        XCTAssertTrue(model.isOpen)
        await store.waitForIdle()
        XCTAssertFalse(model.isOpen)
        var expected = latest
        expected.body = "Corrected transcription"
        XCTAssertEqual(store.stack(id: firstStack)?.notes, [expected, older])
        XCTAssertTrue(store.currentNotes.isEmpty)
    }

    func testFailureRetainsDraftAndRetryCommitsOnlyOnce() async throws {
        let fixture = try await makeStore()
        defer { fixture.store.teardown() }
        await fixture.disk.setFail(true)
        let model = LatestNoteEditor(store: fixture.store)
        model.send(.open)
        model.text = "Keep this correction"
        model.send(.save)
        await fixture.store.waitForIdle()
        guard case .failed(_, _, pending: true) = model.state else { return XCTFail("Expected queued failure") }
        model.send(.dismiss)
        model.send(.discard)
        model.send(.save)
        XCTAssertEqual(model.text, "Keep this correction")
        XCTAssertEqual(fixture.store.currentNotes[0].body, "Original")
        await fixture.disk.setFail(false)
        model.send(.retry)
        await fixture.store.waitForIdle()
        XCTAssertFalse(model.isOpen)
        XCTAssertEqual(fixture.store.currentNotes[0].body, "Keep this correction")
        let attempts = await fixture.disk.attempts
        XCTAssertEqual(attempts, 2)
    }

    func testChangedMovedAndDeletedNotesRejectStaleEdits() async throws {
        for change in 0..<3 {
            let fixture = try await makeStore()
            let store = fixture.store
            defer { store.teardown() }
            let model = LatestNoteEditor(store: store)
            model.send(.open)
            let draft = try XCTUnwrap(model.state.draft)
            model.text = "Stale correction"
            switch change {
            case 0: store.mutate(.updateNoteBody(stackID: draft.stackID, noteID: draft.original.id, body: "Elsewhere"))
            case 1: store.mutate(.moveNoteToStack(noteID: draft.original.id, from: draft.stackID, to: store.stacks[1].id))
            default: store.mutate(.removeNote(stackID: draft.stackID, noteID: draft.original.id))
            }
            await store.waitForIdle()
            let before = store.stacks
            model.send(.save)
            await store.waitForIdle()
            guard case .failed(_, _, pending: false) = model.state else { return XCTFail("Expected stale rejection") }
            XCTAssertEqual(model.text, "Stale correction")
            XCTAssertEqual(store.stacks, before)
        }
    }

    func testDiscardRequiresConfirmationAndOldResultsCannotCloseNewSession() async throws {
        let fixture = try await makeStore()
        defer { fixture.store.teardown() }
        let model = LatestNoteEditor(store: fixture.store)
        model.send(.open)
        let oldID = try XCTUnwrap(model.state.draft?.sessionID)
        model.text = "Draft"
        model.send(.discard)
        XCTAssertTrue(model.isOpen)
        model.send(.dismiss)
        guard case .confirmingDiscard = model.state else { return XCTFail("Expected confirmation") }
        model.send(.save)
        XCTAssertFalse(fixture.store.hasPendingMutations)
        model.send(.keepEditing)
        XCTAssertEqual(model.text, "Draft")
        model.send(.dismiss)
        model.send(.discard)
        XCTAssertFalse(model.isOpen)
        model.send(.open)
        model.text = "New session"
        model.send(.save)
        model.send(.saved(oldID, .committed))
        XCTAssertTrue(model.hasPendingSave)
        await fixture.store.waitForIdle()
        XCTAssertEqual(fixture.store.currentNotes[0].body, "New session")
    }

    func testBlockedEmptyAndPendingOpenDoNotCreateDrafts() async throws {
        let fixture = try await makeStore(notes: [])
        defer { fixture.store.teardown() }
        var blocked: String? = "Capture is active"
        let model = LatestNoteEditor(store: fixture.store, blockedReason: { blocked })
        var messages: [String] = []
        model.onMessage = { messages.append($0) }
        model.send(.open)
        XCTAssertEqual(messages.last, "Capture is active")
        blocked = "Stack edit is active"
        model.send(.open)
        XCTAssertEqual(messages.last, "Stack edit is active")
        blocked = nil
        model.send(.open)
        XCTAssertEqual(messages.last, "No notes to edit")
        fixture.store.mutate(.switchStack(stackID: fixture.store.stacks[1].id))
        model.send(.open)
        XCTAssertEqual(messages.last, "Finish saving pending changes before editing a note.")
        XCTAssertFalse(model.isOpen)
        await fixture.store.waitForIdle()
    }

    func testCancellationAndIdempotentTeardownIgnoreLateResults() async throws {
        let fixture = try await makeStore()
        let model = LatestNoteEditor(store: fixture.store)
        model.send(.open)
        model.text = "Unsaved"
        model.send(.save)
        let id = try XCTUnwrap(model.state.draft?.sessionID)
        fixture.store.teardown()
        guard case .failed(_, _, pending: false) = model.state else { return XCTFail("Expected cancellation") }
        XCTAssertEqual(model.text, "Unsaved")
        var closes = 0
        model.onClose = { closes += 1 }
        model.send(.teardown)
        model.send(.teardown)
        model.send(.saved(id, .committed))
        model.send(.open)
        XCTAssertEqual(closes, 1)
        guard case .tornDown = model.state else { return XCTFail("Must stay torn down") }
    }

    func testExportActionDoesNotTouchClipboardWhileEditorIsOpen() async throws {
        let fixture = try await makeStore()
        let app = AppDelegate()
        let model = LatestNoteEditor(store: fixture.store)
        model.send(.open)
        app.storeState = .available(fixture.store)
        app.latestNoteEditor = LatestNoteEditorWindow(model: model, surfaces: app.surfaces)
        defer {
            app.latestNoteEditor?.teardown()
            app.exportController.teardown()
            app.statusItemController.teardown()
            app.surfaces.teardown()
            fixture.store.teardown()
        }

        let clipboardRevision = NSPasteboard.general.changeCount
        app.perform(.copyMarkdown)

        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardRevision)
        XCTAssertEqual(app.exportController.state, .idle)
        XCTAssertEqual(model.text, "Original")
        XCTAssertTrue(model.isOpen)
    }

    func testRenderAndWindowFocusCloseLifecycle() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce review images.")
        }
        let fixture = try await makeStore(notes: [Note(
            subject: .selection(quote: "A capture should preserve the thought, not interrupt it."),
            body: "Keep the editor focused on this note.\n\nThe original quote should stay attached when I correct the wording."
        )])
        defer { fixture.store.teardown() }
        let model = LatestNoteEditor(store: fixture.store)
        let surfaces = SurfaceCoordinator(setRegularActivation: { _ in })
        let window = LatestNoteEditorWindow(model: model, surfaces: surfaces)
        defer { window.teardown() }
        model.send(.open)
        try await Task.sleep(for: .milliseconds(300))
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Edit latest note" && $0.isVisible })
        let textView = try XCTUnwrap(panel.firstResponder as? NSTextView)
        try write(panel, directory: directory, name: "latest-note-editor")
        textView.insertText("\n\nThis is an unsaved change.",
                            replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        XCTAssertTrue(model.text.hasSuffix("This is an unsaved change."))
        panel.performClose(nil)
        try await Task.sleep(for: .milliseconds(150))
        guard case .confirmingDiscard = model.state else { return XCTFail("Close must ask before discarding") }
        try write(panel, directory: directory, name: "latest-note-discard")
        model.send(.keepEditing)
        panel.performClose(nil)
        guard case .confirmingDiscard = model.state else { return XCTFail("Repeated close must still be intercepted") }
        model.send(.keepEditing)
        await fixture.disk.setFail(true)
        let saveKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
            keyCode: UInt16(kVK_Return)
        ))
        NSApp.sendEvent(saveKey)
        XCTAssertTrue(model.hasPendingSave)
        await fixture.store.waitForIdle()
        try await Task.sleep(for: .milliseconds(150))
        try write(panel, directory: directory, name: "latest-note-save-failed")
        window.teardown()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(surfaces.visible.contains(.latestNoteEditor))

        let standalone = try await makeStore()
        defer { standalone.store.teardown() }
        let plainModel = LatestNoteEditor(store: standalone.store)
        let plainWindow = LatestNoteEditorWindow(model: plainModel, surfaces: surfaces)
        defer { plainWindow.teardown() }
        plainModel.send(.open)
        try await Task.sleep(for: .milliseconds(150))
        let plainPanel = try XCTUnwrap(NSApp.windows.first { $0.title == "Edit latest note" && $0.isVisible })
        try write(plainPanel, directory: directory, name: "latest-note-standalone")
    }

    private func write(_ panel: NSWindow, directory: String, name: String) throws {
        let view = try XCTUnwrap(panel.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func makeStore(notes: [Note] = [Note(subject: .standalone, body: "Original")]) async throws
        -> (store: StackStore, disk: EditorDisk) {
        let stacks = filled([Stack(notes: notes)])
        let document = StackDocument(stacks: stacks, currentStackID: stacks[0].id)
        let disk = EditorDisk()
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { try await disk.commit($0) }))
        return (store, disk)
    }
}

private actor EditorDisk {
    var fail = false
    var attempts = 0
    func setFail(_ fail: Bool) { self.fail = fail }
    func commit(_ document: StackDocument) throws {
        attempts += 1
        if fail { throw StorePersistenceError.invalidDocument("The disk is full.") }
    }
}
