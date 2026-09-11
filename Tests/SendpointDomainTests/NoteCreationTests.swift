import Foundation
import XCTest
import SendpointDomain

final class NoteCreationTests: XCTestCase {
    private let id = UUID()
    private let createdAt = Date(timeIntervalSince1970: 123)
    func testBlankNoteIsRejectedForBothKindsOfSubject() {
        for selection in ["", "Quoted text"] {
            for note in ["", " \n\t "] {
                XCTAssertNil(Note.capturing(
                    selection: selection, body: note, id: id, createdAt: createdAt
                ))
            }
        }
    }

    func testSelectionRetainsFormattingWhileNoteIsTrimmed() throws {
        let quote = "  Original quote\nsecond line  "
        let note = try XCTUnwrap(Note.capturing(
            selection: quote, body: " \n A note \t", id: id, createdAt: createdAt
        ))
        XCTAssertEqual(note, Note(
            id: id, subject: .selection(quote: quote), body: "A note",
            createdAt: createdAt
        ))
    }

    func testMissingOrWhitespaceSelectionCreatesStandaloneNote() throws {
        for selection in ["", " \t\n "] {
            let note = try XCTUnwrap(Note.capturing(
                selection: selection, body: "Note", id: id, createdAt: createdAt
            ))
            XCTAssertEqual(note.subject, .standalone)
            XCTAssertEqual(note.id, id)
            XCTAssertEqual(note.createdAt, createdAt)
        }
    }
}
