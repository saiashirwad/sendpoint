import Foundation

public enum PromptComposer {
    public static func markdown(
        stack: Stack,
        template: Template,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let longDateStyle = Date.FormatStyle(
            date: .long,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        let shortTimeStyle = Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        var blocks: [String] = []

        if template.preamble.nonblank != nil {
            blocks.append(template.preamble)
        }

        if template.includeHeading {
            blocks.append("# Reading notes — \(stack.createdAt.formatted(longDateStyle))")
        }

        for (offset, note) in stack.notes.enumerated() {
            var noteBlocks: [String] = []

            if template.includeNoteNumbers {
                noteBlocks.append("## \(offset + 1)")
            }

            if case let .selection(quote) = note.subject {
                noteBlocks.append(blockquote(quote))
            }

            noteBlocks.append(note.body)

            if template.includeTimestamps {
                noteBlocks.append("_\(note.createdAt.formatted(shortTimeStyle))_")
            }

            blocks.append(noteBlocks.joined(separator: "\n\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    public static func noteMarkdown(_ note: Note) -> String {
        var parts: [String] = []
        if case let .selection(quote) = note.subject, let quote = quote.nonblank {
            parts.append(blockquote(quote))
        }
        if let body = note.body.nonblank { parts.append(body) }
        return parts.joined(separator: "\n\n")
    }

    private static func blockquote(_ quote: String) -> String {
        quote
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }
}
