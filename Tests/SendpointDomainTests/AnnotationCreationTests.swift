import Foundation
import XCTest
import SendpointDomain

final class AnnotationCreationTests: XCTestCase {
    private let id = UUID()
    private let createdAt = Date(timeIntervalSince1970: 123)
    private let application = ApplicationIdentity(name: "Reader", bundleID: "com.example.reader")

    func testBlankNoteIsRejectedForBothKindsOfSubject() {
        for selection in ["", "Quoted text"] {
            for note in ["", " \n\t "] {
                XCTAssertNil(Annotation.capturing(
                    selection: selection, note: note, application: application, id: id, createdAt: createdAt
                ))
            }
        }
    }

    func testSelectionRetainsFormattingAndOriginalIdentityWhileNoteIsTrimmed() throws {
        let quote = "  Original quote\nsecond line  "
        let annotation = try XCTUnwrap(Annotation.capturing(
            selection: quote, note: " \n A note \t", application: application, id: id, createdAt: createdAt
        ))
        XCTAssertEqual(annotation, Annotation(
            id: id, subject: .selection(quote: quote), note: "A note",
            provenance: Provenance(application: application), createdAt: createdAt
        ))
    }

    func testMissingOrWhitespaceSelectionCreatesStandaloneNote() throws {
        for selection in ["", " \t\n "] {
            let annotation = try XCTUnwrap(Annotation.capturing(
                selection: selection, note: "Note", application: application, id: id, createdAt: createdAt
            ))
            XCTAssertEqual(annotation.subject, .standalone)
            XCTAssertEqual(annotation.id, id)
            XCTAssertEqual(annotation.createdAt, createdAt)
        }
    }
}
