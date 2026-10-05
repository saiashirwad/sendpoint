import Foundation

public struct Template: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var preamble: String
    public var includeTimestamps: Bool
    public var includeHeading: Bool
    public var includeNoteNumbers: Bool
    public var clearStackAfterExport: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        preamble: String,
        includeTimestamps: Bool,
        includeHeading: Bool,
        includeNoteNumbers: Bool,
        clearStackAfterExport: Bool = true
    ) {
        self.id = id
        self.name = name
        self.preamble = preamble
        self.includeTimestamps = includeTimestamps
        self.includeHeading = includeHeading
        self.includeNoteNumbers = includeNoteNumbers
        self.clearStackAfterExport = clearStackAfterExport
    }
}

public extension Template {
    static let learn = Template(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Learn",
        preamble: """
        Below are notes I spoke out loud while reading. Each is either a passage I quoted followed by my reaction, or a standalone thought. They're transcribed speech, so expect loose phrasing, half-finished sentences and transcription errors.

        I'm saying these to understand the material, not just to get answers. Read them as a record of how I'm thinking:
        - Where I've got it right, say so briefly and move on.
        - Where I'm wrong or incomplete, show exactly where my reasoning went off and what's actually true.
        - Answer my questions using the mental model I'm already using, then extend it.
        - Point out anything important I seem to have missed.

        Write one connected response, not a reply to each note in turn. Organize it however explains it best, even if that's not the order of my notes. Restate what you're responding to so I don't have to scroll back.
        """,
        includeTimestamps: true,
        includeHeading: true,
        includeNoteNumbers: false,
        clearStackAfterExport: true
    )

    static let steer = Template(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Steer",
        preamble: """
        These are my notes on your previous response. Each quote is something you wrote, followed by my reaction: agreement, a question, an objection, or a change I want. Notes without a quote are general thoughts. They're transcribed speech, so read for intent.

        Treat them as direction. Answer my questions, push back where you think I'm wrong, and say what you'd change as a result. Keep it tight. Don't act on anything yet; we'll keep going until we agree.
        """,
        includeTimestamps: true,
        includeHeading: true,
        includeNoteNumbers: false,
        clearStackAfterExport: true
    )

    static let plain = Template(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Plain",
        preamble: "",
        includeTimestamps: false,
        includeHeading: false,
        includeNoteNumbers: false,
        clearStackAfterExport: true
    )

    static let builtIns: [Template] = [.plain, .learn, .steer]
}
