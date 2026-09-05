import Foundation
import XCTest
@testable import SendpointDomain

final class ProvenanceMutationTests: XCTestCase {
    func testProvenanceOnlyMutationRequiresExactAnnotationAndApplication() throws {
        let app = ApplicationIdentity(name: "Editor", bundleID: "com.microsoft.VSCode")
        let annotation = Annotation(
            subject: .standalone,
            note: "Keep this note",
            provenance: Provenance(application: app)
        )
        let session = Session(name: "Default", entries: [annotation])
        let document = StoreDocument(sessions: [session], currentSessionID: session.id)
        let enriched = Provenance(
            application: app,
            windowTitle: "Main.swift — project",
            url: URL(fileURLWithPath: "/tmp/project/Main.swift")
        )

        let result = SessionDocumentMutations.applying(
            .updateAnnotationProvenance(
                sessionID: session.id,
                annotationID: annotation.id,
                expectedApplication: app,
                provenance: enriched
            ),
            to: document
        )
        guard case let .applied(updated) = result else {
            return XCTFail("Expected provenance update")
        }
        XCTAssertEqual(updated.sessions[0].entries[0].note, annotation.note)
        XCTAssertEqual(updated.sessions[0].entries[0].provenance, enriched)

        let stale = SessionDocumentMutations.applying(
            .updateAnnotationProvenance(
                sessionID: session.id,
                annotationID: annotation.id,
                expectedApplication: ApplicationIdentity(name: "Other"),
                provenance: Provenance(application: ApplicationIdentity(name: "Other"))
            ),
            to: document
        )
        XCTAssertEqual(stale, .noOp)
    }

    func testNoteOnlyAndClearedProvenanceUpdatesNoOpForMissingOrStaleTargets() throws {
        let app = ApplicationIdentity(name: "Editor", bundleID: "com.microsoft.VSCode")
        let annotation = Annotation(
            subject: .standalone,
            note: "Original",
            provenance: Provenance(application: app)
        )
        let session = Session(name: "Default", entries: [annotation])
        let document = StoreDocument(sessions: [session], currentSessionID: session.id)

        XCTAssertEqual(
            SessionDocumentMutations.applying(
                .updateAnnotationNote(
                    sessionID: session.id,
                    annotationID: UUID(),
                    note: "Stale"
                ),
                to: document
            ),
            .noOp
        )
        XCTAssertEqual(
            SessionDocumentMutations.applying(
                .updateAnnotationNote(
                    sessionID: UUID(),
                    annotationID: annotation.id,
                    note: "Stale"
                ),
                to: document
            ),
            .noOp
        )

        guard case let .applied(cleared) = SessionDocumentMutations.applying(
            .clearSession(sessionID: session.id),
            to: document
        ) else { return XCTFail("Expected clear") }
        let enriched = Provenance(application: app, windowTitle: "Focused window")
        let wrongApp = ApplicationIdentity(name: "Other")
        for mutation in [
            SessionDocumentMutation.updateAnnotationProvenance(
                sessionID: UUID(),
                annotationID: annotation.id,
                expectedApplication: app,
                provenance: enriched
            ),
            .updateAnnotationProvenance(
                sessionID: session.id,
                annotationID: UUID(),
                expectedApplication: app,
                provenance: enriched
            ),
            .updateAnnotationProvenance(
                sessionID: session.id,
                annotationID: annotation.id,
                expectedApplication: wrongApp,
                provenance: Provenance(application: wrongApp, windowTitle: "Wrong")
            ),
        ] {
            XCTAssertEqual(SessionDocumentMutations.applying(mutation, to: cleared), .noOp)
        }
    }

}
