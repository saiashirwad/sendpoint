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

/// The file `open` shows: the stack's name, then exactly what `paste` would send.
public func stackDocument(name: String, notes: [Note]) -> String {
    "# \(name)\n\n" + (notes.isEmpty ? "_No notes yet._" : compose(notes)) + "\n"
}
