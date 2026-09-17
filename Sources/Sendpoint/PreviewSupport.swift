import Foundation
import SendpointDomain
import SwiftUI

// MARK: - Preview fixtures
//
// Debug-only scaffolding: inert sample values for `#Preview`s. There is no
// `#if DEBUG` gating precedent in this codebase (no `#if DEBUG` anywhere),
// so this is a plain file: the values ship harmlessly in release, and the
// `#Preview` macros themselves are debug-only by toolchain convention.
// Previews must only use these fixtures plus `.constant` bindings and
// no-op closures — never live singletons, FileManager-backed stores,
// AVAudioEngine, NSAlert, or network.

/// Shared copy for fixtures and previews.
enum PreviewCopy {
    static let shortPassage = "The interface is the instruction."
    static let longPassage =
        "The city's oldest library lends more books in a week than its reading room could ever seat. "
        + "Patrons arrive before opening, leave with stacks that double as furniture, and return them late "
        + "with apologies the librarians long ago stopped recording. What looks like chaos from the desk is, "
        + "from the stacks, a quiet choreography: regulars reshelve for each other, students trade carrels "
        + "without a word, and the new-arrivals shelf fills faster than anyone can catalogue. "
        + "The building remembers what the system forgets."
}

extension Stack {
    static var sample: Stack {
        Stack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Reading",
            notes: [.sample, .sampleLongQuote, .sampleStandalone],
            createdAt: Date(timeIntervalSince1970: 1_727_000_000)
        )
    }
}

extension Note {
    static var sample: Note {
        Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            subject: .selection(quote: PreviewCopy.shortPassage),
            body: "A note about the passage.",
            createdAt: Date(timeIntervalSince1970: 1_727_000_000)
        )
    }

    static var sampleLongQuote: Note {
        Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            subject: .selection(quote: PreviewCopy.longPassage),
            body: "Why the building metaphor works here.",
            createdAt: Date(timeIntervalSince1970: 1_727_000_100)
        )
    }

    static var sampleStandalone: Note {
        Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            subject: .standalone,
            body: "A free-standing thought with no passage.",
            createdAt: Date(timeIntervalSince1970: 1_727_000_200)
        )
    }
}

extension StackItemFacts {
    static var sample: StackItemFacts {
        StackItemFacts(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Reading",
            noteCount: 3,
            isCurrent: true
        )
    }

    static var samplePlain: StackItemFacts {
        StackItemFacts(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            name: "Writing",
            noteCount: 12,
            isCurrent: false
        )
    }
}

extension Template {
    static var sample: Template {
        Template(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
            name: "Sample",
            preamble: "Summarize these notes.",
            includeTimestamps: true,
            includeHeading: true,
            includeNoteNumbers: false,
            clearStackAfterExport: false
        )
    }
}

extension PaletteActionItem {
    static var sample: PaletteActionItem {
        PaletteActionItem(
            action: .newStack,
            title: "New stack",
            keys: "⌘N",
            section: .stack(name: "Reading")
        )
    }

    static var samples: [PaletteActionItem] {
        let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let stackID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        return [
            PaletteActionItem(action: .editNote(noteID), title: "Edit", keys: "↩", section: .note),
            PaletteActionItem(action: .copyNote(noteID), title: "Copy", keys: "⌘C", section: .note),
            PaletteActionItem(
                action: .deleteNote(noteID), title: "Delete", keys: "⌘⌫", section: .note,
                isDestructive: true
            ),
            PaletteActionItem(
                action: .switchToStack(stackID), title: "Switch", keys: "⌘↩",
                section: .stack(name: "Reading")
            ),
            PaletteActionItem(action: .chooseTemplate, title: "Change template", keys: "⌘P", section: .template),
        ]
    }
}

extension VoiceTranscriptRow {
    static var sample: VoiceTranscriptRow {
        VoiceTranscriptRow(id: 0, text: "Hello world")
    }

    static var samples: [VoiceTranscriptRow] {
        [
            VoiceTranscriptRow(id: 0, text: "The library lends more books"),
            VoiceTranscriptRow(id: 1, text: "than the reading room could seat"),
            VoiceTranscriptRow(id: 2, text: "and the building remembers"),
        ]
    }
}
