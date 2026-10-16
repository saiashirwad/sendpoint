import Foundation
import Testing
@testable import Core

private func run(_ events: [Event], from start: World = World()) -> (World, [Effect]) {
    var w = start
    var effects: [Effect] = []
    for e in events { effects += step(&w, e) }
    return (w, effects)
}

@Test func typedNoteLandsInActiveStack() {
    let (w, fx) = run([.select(2), .capture(selection: "quoted"), .edit("thought"), .commit])
    #expect(w.mode == .idle)
    #expect(w.stacks[2] == [Note(quote: "quoted", body: "thought")])
    #expect(fx == [.save, .save])
}

@Test func switchingStackWhileDraftingMovesTheDestination() {
    let (w, _) = run([.capture(selection: "q"), .select(3), .edit("b"), .commit])
    #expect(w.stacks[0].isEmpty)
    #expect(w.stacks[3] == [Note(quote: "q", body: "b")])
}

@Test func emptyNoteIsDropped() {
    let (w, fx) = run([.capture(selection: "  "), .edit("\n"), .commit])
    #expect(w.stacks.joined().isEmpty)
    #expect(fx.isEmpty)
}

@Test func holdToTalkAppendsFinalText() {
    let (w, fx) = run([
        .capture(selection: "q"), .edit("typed"),
        .speakDown(selection: "ignored"),
        .partial(take: 1, "hel"),
        .speakUp(tap: false),
        .final(take: 1, "hello there"),
    ])
    #expect(w.mode == .drafting(Draft(quote: "q", body: "typed hello there")))
    #expect(fx == [.micStart(take: 1), .micStop(take: 1)])
}

@Test func speakingFromIdleCapturesTheSelection() {
    let (w, fx) = run([.speakDown(selection: "sel"), .partial(take: 1, "hi")])
    #expect(w.mode == .listening(Draft(quote: "sel"), partial: "hi"))
    #expect(fx == [.micStart(take: 1)])
}

@Test func tapLatchesUntilNextPress() {
    let (w, fx) = run([.speakDown(selection: ""), .speakUp(tap: true)])
    #expect(fx == [.micStart(take: 1)])
    guard case .listening = w.mode else { Issue.record("should still listen"); return }
    let (_, more) = run([.speakDown(selection: "")], from: w)
    #expect(more == [.micStop(take: 1)])
}

@Test func staleSpeechResultsAreIgnored() {
    let (w, fx) = run([
        .speakDown(selection: ""), .cancel,          // take 1 cancelled
        .speakDown(selection: ""),                   // take 2
        .partial(take: 1, "old"), .final(take: 1, "old"),
        .final(take: 2, "new"),
    ])
    #expect(w.mode == .drafting(Draft(quote: "", body: "new")))
    #expect(fx == [.micStart(take: 1), .micCancel, .micStart(take: 2)])
}

@Test func resultsAfterCancelDoNothing() {
    let (w, _) = run([.speakDown(selection: ""), .cancel, .final(take: 1, "late")])
    #expect(w.mode == .idle)
    #expect(w.stacks.joined().isEmpty)
}

@Test func invalidTransitionsAreNoOps() {
    let start = World()
    for e: Event in [.commit, .cancel, .edit("x"), .speakUp(tap: false), .final(take: 0, "x"), .select(9), .select(-1), .paste] {
        let (w, fx) = run([e], from: start)
        #expect(w == start, "\(e)")
        #expect(fx.isEmpty, "\(e)")
    }
}

@Test func editsAreIgnoredWhileListening() {
    let (w, _) = run([.speakDown(selection: ""), .edit("x"), .commit])
    #expect(w.mode == .listening(Draft(quote: ""), partial: ""))
}

@Test func pasteComposesAndClearsOnlyTheActiveStack() {
    var start = World()
    start.stacks[0] = [Note(quote: "a\n\nb", body: "one"), Note(quote: "", body: "two")]
    start.stacks[1] = [Note(quote: "", body: "keep")]
    let (w, fx) = run([.paste], from: start)
    #expect(fx == [.paste("> a\n>\n> b\n\none\n\n---\n\ntwo"), .save])
    #expect(w.stacks[0].isEmpty)
    #expect(w.stacks[1].count == 1)
}

@Test func pasteIsBlockedWhileDrafting() {
    var start = World()
    start.stacks[0] = [Note(quote: "", body: "x")]
    let (w, fx) = run([.capture(selection: ""), .paste], from: start)
    #expect(fx.isEmpty)
    #expect(w.stacks[0].count == 1)
}

@Test func savedRoundTripsAndRepairsShape() {
    var w = World()
    w.stacks[1] = [Note(quote: "q", body: "b")]
    w.active = 1
    w.mode = .drafting(Draft(quote: "session only"))
    let back = Saved.decode(Saved.encode(w))
    #expect(back?.stacks == w.stacks)
    #expect(back?.active == 1)
    #expect(back?.mode == .idle)

    let short = Data(#"{"stacks":[[]],"active":7}"#.utf8)
    #expect(Saved.decode(short)?.stacks.count == stackCount)
    #expect(Saved.decode(short)?.active == 0)
}
