import Foundation
import XCTest
import SendpointDomain

final class NoteListingTests: XCTestCase {
    private let firstNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let secondNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let thirdNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    private var notes: [Note] {
        [
            Note(
                id: firstNoteID,
                subject: .selection(quote: "OT scales quadratically"),
                body: "Can you explain why?"
            ),
            Note(
                id: secondNoteID,
                subject: .standalone,
                body: "Monoids and semi-groups"
            ),
            Note(
                id: thirdNoteID,
                subject: .selection(quote: "join-semilattice"),
                body: ""
            ),
        ]
    }

    func testNoteListingSearchesQuoteAndNote() {
        let all = NoteListing(notes: notes, query: "  ")
        XCTAssertEqual(all.ids, [firstNoteID, secondNoteID, thirdNoteID])

        XCTAssertEqual(NoteListing(notes: notes, query: "QUADRAT").ids, [firstNoteID], "quote")
        XCTAssertEqual(NoteListing(notes: notes, query: "monoid").ids, [secondNoteID], "note")
        XCTAssertTrue(NoteListing(notes: notes, query: "zzz").isEmpty)
    }


    func testSearchFoldsCaseDiacriticsAndWidthWithoutReordering() {
        let matching = Note(subject: .standalone, body: "Ｃａｆé")
        let listing = NoteListing(notes: [notes[0], matching, notes[1]], query: "  CAFE  ")
        XCTAssertEqual(listing.notes, [matching])
        XCTAssertTrue(NoteListing(notes: [], query: "anything").isEmpty)
    }
}
