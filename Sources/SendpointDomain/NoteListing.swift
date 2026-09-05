import Foundation

/// The notes of one stack that match a query. Matching is case- and
/// diacritic-insensitive over the quote, the note, the app, and the window.
public struct NoteListing: Equatable, Sendable {
    public let entries: [Annotation]

    public init(entries: [Annotation], query: String) {
        self.entries = entries.matching(query) { entry in
            var parts = [entry.note, entry.provenance.application.name]
            if case let .selection(quote) = entry.subject { parts.append(quote) }
            if let window = entry.provenance.windowTitle { parts.append(window) }
            return parts.joined(separator: "\n")
        }
    }

    public var ids: [UUID] { entries.map(\.id) }
    public var isEmpty: Bool { entries.isEmpty }
}
