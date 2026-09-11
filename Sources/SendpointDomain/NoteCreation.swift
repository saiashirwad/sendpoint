import Foundation

public extension Note {
    /// Creates a note from captured values. Whitespace-only bodies are rejected;
    /// quotes retain their original formatting and IDs/timestamps are never regenerated.
    static func capturing(
        selection: String,
        body: String,
        id: UUID,
        createdAt: Date
    ) -> Self? {
        guard let body = body.nonblank else { return nil }
        return Self(
            id: id,
            subject: selection.nonblank == nil ? .standalone : .selection(quote: selection),
            body: body,
            createdAt: createdAt
        )
    }
}
