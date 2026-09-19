import Foundation

public extension Note {
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
