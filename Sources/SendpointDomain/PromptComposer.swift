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

        if !template.preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

            let metadata = metadata(
                for: note,
                template: template,
                shortTimeStyle: shortTimeStyle
            )
            if !metadata.isEmpty {
                noteBlocks.append("_\(metadata.joined(separator: " · "))_")
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

    private static func metadata(
        for note: Note,
        template: Template,
        shortTimeStyle: Date.FormatStyle
    ) -> [String] {
        var facts: [String] = []

        if template.includeApplication {
            appendIfPresent(note.provenance.application.name, to: &facts)
        }
        if template.includeWindow {
            appendIfPresent(note.provenance.windowTitle, to: &facts)
        }
        if template.includeLink {
            if let url = note.provenance.url {
                appendIfPresent(displayLink(url), to: &facts)
            }
            if let directory = note.provenance.workingDirectory {
                appendIfPresent(abbreviatedPath(directory), to: &facts)
            }
        }

        if template.includeTimestamps {
            facts.append(note.createdAt.formatted(shortTimeStyle))
        }

        return facts
    }

    private static func appendIfPresent(_ value: String?, to values: inout [String]) {
        guard
            let value,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        values.append(value)
    }

    private static func displayLink(_ url: URL) -> String {
        url.isFileURL ? abbreviatedPath(url) : url.absoluteString
    }

    private static func abbreviatedPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
