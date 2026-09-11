import Foundation
import XCTest
import SendpointDomain

final class NoteCreationTests: XCTestCase {
    private let id = UUID()
    private let createdAt = Date(timeIntervalSince1970: 123)
    private let application = ApplicationIdentity(name: "Reader", bundleID: "com.example.reader")

    func testBlankNoteIsRejectedForBothKindsOfSubject() {
        for selection in ["", "Quoted text"] {
            for note in ["", " \n\t "] {
                XCTAssertNil(Note.capturing(
                    selection: selection, body: note, application: application, id: id, createdAt: createdAt
                ))
            }
        }
    }

    func testSelectionRetainsFormattingAndOriginalIdentityWhileNoteIsTrimmed() throws {
        let quote = "  Original quote\nsecond line  "
        let note = try XCTUnwrap(Note.capturing(
            selection: quote, body: " \n A note \t", application: application, id: id, createdAt: createdAt
        ))
        XCTAssertEqual(note, Note(
            id: id, subject: .selection(quote: quote), body: "A note",
            provenance: Provenance(application: application), createdAt: createdAt
        ))
    }

    func testMissingOrWhitespaceSelectionCreatesStandaloneNote() throws {
        for selection in ["", " \t\n "] {
            let note = try XCTUnwrap(Note.capturing(
                selection: selection, body: "Note", application: application, id: id, createdAt: createdAt
            ))
            XCTAssertEqual(note.subject, .standalone)
            XCTAssertEqual(note.id, id)
            XCTAssertEqual(note.createdAt, createdAt)
        }
    }
}
