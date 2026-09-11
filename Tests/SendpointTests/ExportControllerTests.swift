import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class ExportControllerTests: XCTestCase {
    private let annotation = Annotation(
        subject: .standalone,
        note: "A note",
        provenance: Provenance(application: ApplicationIdentity(name: "Reader"))
    )

    func testClipboardWriteFailureDoesNotClear() async throws {
        let session = Session(name: "Default", entries: [annotation])
        let store = try await AnnotationStore(
            persistence: StorePersistence(load: { nil }, commit: { _ in }), defaultSession: session
        )
        var profile = Profile.plain
        profile.clearSessionAfterExport = true
        var attemptedText = ""
        let exporter = ExportController(services: ExportServices(
            write: { text in attemptedText = text; return nil },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, sessionID: session.id, profile: profile) { _ in }
        await store.waitForIdle()

        if case .failed = exporter.state {} else { XCTFail("Expected clipboard failure") }
        XCTAssertFalse(attemptedText.isEmpty)
        XCTAssertEqual(store.currentEntries, [annotation])
        store.teardown()
    }

    func testSuccessfulWriteUsesTheProfileAndClearsTheSession() async throws {
        let session = Session(name: "Default", entries: [annotation])
        let store = try await AnnotationStore(
            persistence: StorePersistence(load: { nil }, commit: { _ in }), defaultSession: session
        )
        var profile = Profile.plain
        profile.preamble = "Use this profile"
        profile.clearSessionAfterExport = true
        var written = ""
        let exporter = ExportController(services: ExportServices(
            write: { markdown in written = markdown; return 1 },
            paste: { _, _ in XCTFail("Must not paste"); return false }
        ))

        exporter.copy(store: store, sessionID: session.id, profile: profile) { _ in }
        await store.waitForIdle()

        XCTAssertEqual(exporter.state, .idle)
        XCTAssertEqual(written, "Use this profile\n\nA note")
        XCTAssertTrue(store.currentEntries.isEmpty)
        XCTAssertEqual(store.lastCleared?.entries, [annotation])
        store.teardown()
    }
}
