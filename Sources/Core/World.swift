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
    case listening(Draft, partial: String)
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

    public init(stacks: [[Note]] = Array(repeating: [], count: stackCount), active: Int = 0) {
        self.stacks = stacks
        self.active = active
    }
}

public enum Event: Equatable, Sendable {
    case capture(selection: String)
    case speakDown(selection: String)
    /// `tap` means the key was released quickly: keep listening until the next press.
    case speakUp(tap: Bool)
    case partial(take: Int, String)
    case final(take: Int, String)
    case edit(String)
    case commit
    case cancel
    case select(Int)
    case paste
}

public enum Effect: Equatable, Sendable {
    case micStart(take: Int)
    case micStop(take: Int)
    case micCancel
    case paste(String)
    case save
}

public func step(_ w: inout World, _ event: Event) -> [Effect] {
    switch (w.mode, event) {
    case (.idle, .capture(let selection)):
        w.mode = .drafting(Draft(quote: selection))
        return []

    case (.idle, .speakDown(let selection)):
        return listen(&w, Draft(quote: selection))
    case (.drafting(let draft), .speakDown):
        return listen(&w, draft)
    case (.listening, .speakDown):
        return [.micStop(take: w.take)]
    case (.listening, .speakUp(tap: false)):
        return [.micStop(take: w.take)]

    case (.listening(let draft, _), .partial(let take, let text)) where take == w.take:
        w.mode = .listening(draft, partial: text)
        return []
    case (.listening(var draft, _), .final(let take, let text)) where take == w.take:
        draft.body = joined(draft.body, text)
        w.mode = .drafting(draft)
        return []

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

    default:
        return []
    }
}

private func listen(_ w: inout World, _ draft: Draft) -> [Effect] {
    w.take += 1
    w.mode = .listening(draft, partial: "")
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
