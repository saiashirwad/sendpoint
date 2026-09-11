import Foundation

/// The notes of one stack that match a query. Matching is case- and
/// diacritic-insensitive over the quote, the note, the app, and the window.
public struct NoteListing: Equatable, Sendable {
    public let notes: [Note]

    public init(notes: [Note], query: String) {
        self.notes = notes.matching(query) { note in
            var parts = [note.body, note.provenance.application.name]
            if case let .selection(quote) = note.subject { parts.append(quote) }
            if let window = note.provenance.windowTitle { parts.append(window) }
            return parts.joined(separator: "\n")
        }
    }

    public var ids: [UUID] { notes.map(\.id) }
    public var isEmpty: Bool { notes.isEmpty }
}
