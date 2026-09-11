import Foundation
import XCTest
@testable import SendpointDomain

final class ProvenanceMutationTests: XCTestCase {
    func testProvenanceOnlyMutationRequiresExactNoteAndApplication() throws {
        let app = ApplicationIdentity(name: "Editor", bundleID: "com.microsoft.VSCode")
        let note = Note(
            subject: .standalone,
            body: "Keep this note",
            provenance: Provenance(application: app)
        )
        let stack = Stack(name: "Default", notes: [note])
        let document = StackDocument(stacks: [stack], currentStackID: stack.id)
        let enriched = Provenance(
            application: app,
            windowTitle: "Main.swift — project",
            url: URL(fileURLWithPath: "/tmp/project/Main.swift")
        )

        let result = StackDocumentMutations.applying(
            .updateNoteProvenance(
                stackID: stack.id,
                noteID: note.id,
                expectedApplication: app,
                provenance: enriched
            ),
            to: document
        )
        guard case let .applied(updated) = result else {
            return XCTFail("Expected provenance update")
        }
        XCTAssertEqual(updated.stacks[0].notes[0].body, note.body)
        XCTAssertEqual(updated.stacks[0].notes[0].provenance, enriched)

        let stale = StackDocumentMutations.applying(
            .updateNoteProvenance(
                stackID: stack.id,
                noteID: note.id,
                expectedApplication: ApplicationIdentity(name: "Other"),
                provenance: Provenance(application: ApplicationIdentity(name: "Other"))
            ),
            to: document
        )
        XCTAssertEqual(stale, .noOp)
    }

    func testNoteOnlyAndClearedProvenanceUpdatesNoOpForMissingOrStaleTargets() throws {
        let app = ApplicationIdentity(name: "Editor", bundleID: "com.microsoft.VSCode")
        let note = Note(
            subject: .standalone,
            body: "Original",
            provenance: Provenance(application: app)
        )
        let stack = Stack(name: "Default", notes: [note])
        let document = StackDocument(stacks: [stack], currentStackID: stack.id)

        XCTAssertEqual(
            StackDocumentMutations.applying(
                .updateNoteBody(
                    stackID: stack.id,
                    noteID: UUID(),
                    body: "Stale"
                ),
                to: document
            ),
            .noOp
        )
        XCTAssertEqual(
            StackDocumentMutations.applying(
                .updateNoteBody(
                    stackID: UUID(),
                    noteID: note.id,
                    body: "Stale"
                ),
                to: document
            ),
            .noOp
        )

        guard case let .applied(cleared) = StackDocumentMutations.applying(
            .clearStack(stackID: stack.id),
            to: document
        ) else { return XCTFail("Expected clear") }
        let enriched = Provenance(application: app, windowTitle: "Focused window")
        let wrongApp = ApplicationIdentity(name: "Other")
        for mutation in [
            StackDocumentMutation.updateNoteProvenance(
                stackID: UUID(),
                noteID: note.id,
                expectedApplication: app,
                provenance: enriched
            ),
            .updateNoteProvenance(
                stackID: stack.id,
                noteID: UUID(),
                expectedApplication: app,
                provenance: enriched
            ),
            .updateNoteProvenance(
                stackID: stack.id,
                noteID: note.id,
                expectedApplication: wrongApp,
                provenance: Provenance(application: wrongApp, windowTitle: "Wrong")
            ),
        ] {
            XCTAssertEqual(StackDocumentMutations.applying(mutation, to: cleared), .noOp)
        }
    }

}
