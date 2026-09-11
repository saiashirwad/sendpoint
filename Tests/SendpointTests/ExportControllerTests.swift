import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class ExportControllerTests: XCTestCase {
    private let note = Note(
        subject: .standalone,
        body: "A note"
    )

    func testClipboardWriteFailureDoesNotClear() async throws {
        let stack = Stack(name: "Default", notes: [note])
        let store = try await StackStore(
            persistence: StorePersistence(load: { nil }, commit: { _ in }), defaultStack: stack
        )
        var template = Template.plain
        template.clearStackAfterExport = true
        var attemptedText = ""
        let exporter = ExportController(services: ExportServices(
            write: { text in attemptedText = text; return nil },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, stackID: stack.id, template: template) { _ in }
        await store.waitForIdle()

        if case .failed = exporter.state {} else { XCTFail("Expected clipboard failure") }
        XCTAssertFalse(attemptedText.isEmpty)
        XCTAssertEqual(store.currentNotes, [note])
        store.teardown()
    }

    func testSuccessfulWriteUsesTheTemplateAndClearsTheStack() async throws {
        let stack = Stack(name: "Default", notes: [note])
        let store = try await StackStore(
            persistence: StorePersistence(load: { nil }, commit: { _ in }), defaultStack: stack
        )
        var template = Template.plain
        template.preamble = "Use this template"
        template.clearStackAfterExport = true
        var written = ""
        let exporter = ExportController(services: ExportServices(
            write: { markdown in written = markdown; return 1 },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, stackID: stack.id, template: template) { _ in }
        await store.waitForIdle()

        XCTAssertEqual(exporter.state, .idle)
        XCTAssertEqual(written, "Use this template\n\nA note")
        XCTAssertTrue(store.currentNotes.isEmpty)
        XCTAssertEqual(store.lastCleared?.notes, [note])
        store.teardown()
    }
}
