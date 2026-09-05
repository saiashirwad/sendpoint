import Foundation

public extension Annotation {
    /// Creates a note from captured values. Whitespace-only notes are rejected;
    /// quotes retain their original formatting and IDs/timestamps are never regenerated.
    static func capturing(
        selection: String,
        note: String,
        application: ApplicationIdentity,
        id: UUID,
        createdAt: Date
    ) -> Self? {
        guard let note = note.nonblank else { return nil }
        return Self(
            id: id,
            subject: selection.nonblank == nil ? .standalone : .selection(quote: selection),
            note: note,
            provenance: Provenance(application: application),
            createdAt: createdAt
        )
    }
}
