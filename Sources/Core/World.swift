import Foundation

// All of Sendpoint's behavior. The app feeds Events into `step` and carries
// out the Effects it returns; nothing else decides anything.

public let stackCount = 4

public struct Note: Codable, Equatable, Sendable {
    public var quote: String
    public var body: String

    public init(quote: String, body: String) {
        self.quote = quote
        self.body = body
    }
}

public enum Mode: Equatable, Sendable {
    case idle
    case drafting(Draft)
    /// `save`: commit the note when the speech ends. True when speaking started with no card open.
    case listening(Draft, partial: String, save: Bool)
}

public struct Draft: Equatable, Sendable {
    public var quote: String
    public var body: String

    public init(quote: String, body: String = "") {
        self.quote = quote
        self.body = body
    }
}

public struct World: Equatable, Sendable {
    public var stacks: [[Note]]
    public var active: Int
    public var mode: Mode = .idle
    /// Incremented per recording. Speech results carry it; a mismatch is stale.
    public var take = 0
    /// From ~/.config/sendpoint/config.toml. Not saved with the notes.
    public var config = Config()

    public init(stacks: [[Note]] = Array(repeating: [], count: stackCount), active: Int = 0) {
        self.stacks = stacks
        self.active = active
    }
}

public enum Event: Equatable, Sendable {
    case capture(selection: String)
    case speakDown(selection: String)
    case speakUp
    case partial(take: Int, String)
    case final(take: Int, String)
    case edit(String)
    case commit
    case cancel
    case select(Int)
    case paste
    case open
    case configure(Config)
}

public enum Effect: Equatable, Sendable {
    case micStart(take: Int)
    case micStop(take: Int)
    case micCancel
    case paste(String)
    case save
    /// Write stack N's Markdown file and open it in the user's editor.
    case open(Int)
    /// Re-register the global shortcuts from `world.config.keys`.
    case bindKeys
}

public func step(_ w: inout World, _ event: Event) -> [Effect] {
    switch (w.mode, event) {
    case (.idle, .capture(let selection)):
        w.mode = .drafting(Draft(quote: selection))
        return []

    // Hold: press starts, release stops. Tap: press starts, the next press stops.
    case (.idle, .speakDown(let selection)):
        return listen(&w, Draft(quote: selection), save: true)
    case (.drafting(let draft), .speakDown):
        return listen(&w, draft, save: false)
    case (.listening, .speakDown) where w.config.voice == .tap:
        return [.micStop(take: w.take)]
    case (.listening, .speakUp) where w.config.voice == .hold:
        return [.micStop(take: w.take)]

    case (.listening(let draft, _, let save), .partial(let take, let text)) where take == w.take:
        w.mode = .listening(draft, partial: text, save: save)
        return []
    case (.listening(var draft, _, let save), .final(let take, let text)) where take == w.take:
        draft.body = joined(draft.body, text)
        w.mode = .drafting(draft)
        // Nothing heard: leave the card open to type into rather than saving a bare quote.
        guard save, !trimmed(text).isEmpty else { return [] }
        return step(&w, .commit)

    case (.drafting(var draft), .edit(let text)):
        draft.body = text
        w.mode = .drafting(draft)
        return []

    case (.drafting(let draft), .commit):
        w.mode = .idle
        let note = Note(quote: trimmed(draft.quote), body: trimmed(draft.body))
        guard !note.quote.isEmpty || !note.body.isEmpty else { return [] }
        w.stacks[w.active].append(note)
        return [.save]

    case (.drafting, .cancel):
        w.mode = .idle
        return []
    case (.listening, .cancel):
        w.mode = .idle
        return [.micCancel]

    case (_, .select(let index)) where w.stacks.indices.contains(index) && index != w.active:
        w.active = index
        return [.save]

    case (.idle, .paste) where !w.stacks[w.active].isEmpty:
        let markdown = compose(w.stacks[w.active])
        w.stacks[w.active] = []
        return [.paste(markdown), .save]

    case (.idle, .open):
        return [.open(w.active)]

    case (_, .configure(let config)):
        let rebind = config.keys != w.config.keys
        w.config = config
        return rebind ? [.bindKeys] : []

    default:
        return []
    }
}

private func listen(_ w: inout World, _ draft: Draft, save: Bool) -> [Effect] {
    w.take += 1
    w.mode = .listening(draft, partial: "", save: save)
    return [.micStart(take: w.take)]
}

func joined(_ body: String, _ spoken: String) -> String {
    let spoken = trimmed(spoken)
    if spoken.isEmpty { return body }
    if trimmed(body).isEmpty { return spoken }
    return body.last?.isWhitespace == true ? body + spoken : body + " " + spoken
}

func trimmed(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}
