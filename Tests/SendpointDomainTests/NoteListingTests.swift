import Foundation
import XCTest
import SendpointDomain

final class NoteListingTests: XCTestCase {
    private let firstNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let secondNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let thirdNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    private var entries: [Annotation] {
        [
            Annotation(
                id: firstNoteID,
                subject: .selection(quote: "OT scales quadratically"),
                note: "Can you explain why?",
                provenance: Provenance(
                    application: ApplicationIdentity(name: "Helium"),
                    windowTitle: "CRDT deep dive",
                    url: URL(string: "https://example.com/crdt")
                )
            ),
            Annotation(
                id: secondNoteID,
                subject: .standalone,
                note: "Monoids and semi-groups",
                provenance: Provenance(application: ApplicationIdentity(name: "Safari"))
            ),
            Annotation(
                id: thirdNoteID,
                subject: .selection(quote: "join-semilattice"),
                note: "",
                provenance: Provenance(application: ApplicationIdentity(name: "Helium"))
            ),
        ]
    }

    func testNoteListingSearchesQuoteNoteAppAndWindow() {
        let all = NoteListing(entries: entries, query: "  ")
        XCTAssertEqual(all.ids, [firstNoteID, secondNoteID, thirdNoteID])

        XCTAssertEqual(NoteListing(entries: entries, query: "QUADRAT").ids, [firstNoteID], "quote")
        XCTAssertEqual(NoteListing(entries: entries, query: "monoid").ids, [secondNoteID], "note")
        XCTAssertEqual(
            NoteListing(entries: entries, query: "helium").ids, [firstNoteID, thirdNoteID], "app")
        XCTAssertEqual(NoteListing(entries: entries, query: "deep dive").ids, [firstNoteID], "window")
        XCTAssertTrue(NoteListing(entries: entries, query: "zzz").isEmpty)
    }


    func testSearchFoldsCaseDiacriticsAndWidthWithoutReordering() {
        let matching = Annotation(
            subject: .standalone, note: "Ｃａｆé", provenance: Provenance(application: ApplicationIdentity(name: "Reader"))
        )
        let listing = NoteListing(entries: [entries[0], matching, entries[1]], query: "  CAFE  ")
        XCTAssertEqual(listing.entries, [matching])
        XCTAssertTrue(NoteListing(entries: [], query: "anything").isEmpty)
    }
}
