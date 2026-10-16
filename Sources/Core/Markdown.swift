public func compose(_ notes: [Note]) -> String {
    notes.map { note in
        [blockquote(note.quote), note.body].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }.joined(separator: "\n\n---\n\n")
}

func blockquote(_ quote: String) -> String {
    guard !quote.isEmpty else { return "" }
    return quote.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? ">" : "> \($0)" }
        .joined(separator: "\n")
}
