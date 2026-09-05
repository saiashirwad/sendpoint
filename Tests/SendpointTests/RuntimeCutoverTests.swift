import AppKit
import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

final class RuntimeCutoverTests: XCTestCase {
    func testTypedSelectionWithoutNoteIsRejectedAtCaptureBoundary() {
        let context = AnnotationCaptureContext(sessionID: UUID())
        let target = context.target(captured: CapturedSelection(
            text: "Selected text",
            appName: "Reader",
            appBundleID: "com.example.reader",
            screenRect: nil
        ))

        XCTAssertNil(CaptureAnnotationPolicy.annotation(for: target, note: "  \n "))
    }

    func testCaptureContextSuppliedIdentifiersSessionAndDateSurviveTargetConstruction() throws {
        let sessionID = UUID()
        let captureID = UUID()
        let annotationID = UUID()
        let createdAt = Date(timeIntervalSince1970: 123)
        let context = AnnotationCaptureContext(
            sessionID: sessionID,
            captureID: captureID,
            annotationID: annotationID,
            createdAt: createdAt
        )
        let target = context.target(captured: CapturedSelection(
            text: " quote ",
            appName: "Reader",
            appBundleID: "com.example.reader",
            processIdentifier: 123,
            screenRect: nil
        ))

        let annotation = try XCTUnwrap(
            CaptureAnnotationPolicy.annotation(for: target, note: "  My note  ")
        )
        XCTAssertEqual(target.sessionID, sessionID)
        XCTAssertEqual(target.captureID, captureID)
        XCTAssertEqual(target.annotationID, annotationID)
        XCTAssertEqual(target.createdAt, createdAt)
        XCTAssertEqual(target.captured.processIdentifier, 123)
        XCTAssertEqual(annotation.id, annotationID)
        XCTAssertEqual(annotation.createdAt, createdAt)
        XCTAssertEqual(annotation.note, "My note")
        XCTAssertEqual(annotation.provenance.application.name, "Reader")
        XCTAssertEqual(annotation.provenance.application.bundleID, "com.example.reader")
        XCTAssertEqual(annotation.subject, .selection(quote: " quote "))
    }

    @MainActor
    func testCapturePanelCloseHandlerIsOneShot() {
        let panel = CapturePanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        var closeCount = 0
        panel.onClose = { closeCount += 1 }

        panel.performClose(nil)
        panel.performClose(nil)

        XCTAssertEqual(closeCount, 1)
        XCTAssertNil(panel.onClose)
    }

    @MainActor
    func testClipboardWriteFailureDoesNotClear() async throws {
        let annotation = Annotation(
            subject: .standalone,
            note: "Keep me",
            provenance: Provenance(application: ApplicationIdentity(name: "Reader"))
        )
        let session = Session(name: "Default", entries: [annotation])
        let persistence = StorePersistence(load: { nil }, commit: { _ in })
        let store = try await AnnotationStore(persistence: persistence, defaultSession: session)
        var attemptedText = ""
        var profile = Profile.plain
        profile.clearSessionAfterExport = true

        let exporter = ExportController(services: ExportServices(write: { text in
            attemptedText = text
            return nil
        }, paste: { _, _ in XCTFail("Must not paste"); return false }))
        exporter.copy(store: store, sessionID: session.id, profile: profile) { _ in }
        await store.waitForIdle()

        if case .failed = exporter.state {} else { XCTFail("Expected clipboard failure") }
        XCTAssertFalse(attemptedText.isEmpty)
        XCTAssertEqual(store.currentEntries, [annotation])
        store.teardown()
    }

    @MainActor
    func testSettingsActiveProfileShapesExportAndSuccessfulWriteClearsSession() async throws {
        let suite = "RuntimeCutoverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var profile = Profile.plain
        profile = Profile(
            id: UUID(),
            name: "Export and Clear",
            preamble: "Use this profile",
            includeApplication: false,
            includeWindow: false,
            includeLink: false,
            includeTimestamps: false,
            includeHeading: false,
            clearSessionAfterExport: true
        )
        try settings.addProfile(profile)
        try settings.selectProfile(id: profile.id)

        let annotation = Annotation(
            subject: .standalone,
            note: "A note",
            provenance: Provenance(application: ApplicationIdentity(name: "Reader"))
        )
        let session = Session(name: "Default", entries: [annotation])
        let persistence = StorePersistence(load: { nil }, commit: { _ in })
        let store = try await AnnotationStore(persistence: persistence, defaultSession: session)
        var written = ""

        let exporter = ExportController(services: ExportServices(write: { markdown in
            written = markdown
            return 1
        }, paste: { _, _ in XCTFail("Must not paste"); return false }))
        exporter.copy(store: store, sessionID: session.id, profile: settings.activeProfile) { _ in }
        await store.waitForIdle()

        XCTAssertEqual(exporter.state, .idle)
        XCTAssertEqual(written, "Use this profile\n\n## 1\n\nA note")
        XCTAssertTrue(store.currentEntries.isEmpty)
        XCTAssertEqual(store.lastCleared?.entries, [annotation])
        store.teardown()
    }

}
