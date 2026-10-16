import Foundation
import Testing
@testable import Core

/// A world whose voice model is in, as it is once launch finishes.
private func ready() -> World {
    var w = World()
    w.voice = .ready
    return w
}

private func run(_ events: [Event], from start: World = ready()) -> (World, [Effect]) {
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

private func tapMode() -> World {
    var w = ready()
    w.config.voice = .tap
    return w
}

@Test func holdTalksWhileDownAndSavesOnRelease() {
    let (w, fx) = run([
        .speakDown(selection: "sel"),
        .partial(take: 1, "hel"),
        .speakDown(selection: ""),          // a repeat press while holding does nothing
        .speakUp,
        .final(take: 1, "hello there"),
    ])
    #expect(w.mode == .idle)
    #expect(w.stacks[0] == [Note(quote: "sel", body: "hello there")])
    #expect(fx == [.micStart(take: 1), .micStop(take: 1), .save])
}

@Test func tapStartsAndTheNextTapStopsAndSaves() {
    let (w, fx) = run([.speakDown(selection: "sel"), .speakUp], from: tapMode())
    #expect(fx == [.micStart(take: 1)])
    #expect(w.mode == .listening(Draft(quote: "sel"), partial: "", save: true))

    let (done, more) = run([.speakDown(selection: ""), .speakUp, .final(take: 1, "said")], from: w)
    #expect(more == [.micStop(take: 1), .save])
    #expect(done.mode == .idle)
    #expect(done.stacks[0] == [Note(quote: "sel", body: "said")])
}

@Test func speakingIntoAnOpenCardAppendsAndKeepsItOpen() {
    let (w, fx) = run([
        .capture(selection: "q"), .edit("typed"),
        .speakDown(selection: "ignored"), .speakUp,
        .final(take: 1, "hello there"),
    ])
    #expect(w.mode == .drafting(Draft(quote: "q", body: "typed hello there")))
    #expect(w.stacks[0].isEmpty)
    #expect(fx == [.micStart(take: 1), .micStop(take: 1)])
}

@Test func hearingNothingLeavesTheCardOpenInsteadOfSaving() {
    let (w, fx) = run([.speakDown(selection: "sel"), .speakUp, .final(take: 1, " ")])
    #expect(w.mode == .drafting(Draft(quote: "sel")))
    #expect(w.stacks[0].isEmpty)
    #expect(fx == [.micStart(take: 1), .micStop(take: 1)])
}

@Test func speakingBeforeTheModelIsInOpensTheCardForTyping() {
    let (w, fx) = run([.voice(.downloading(42)), .speakDown(selection: "sel"), .speakUp, .speakDown(selection: "")],
                      from: World())
    #expect(w.voice == .downloading(42))
    #expect(w.mode == .drafting(Draft(quote: "sel")))
    #expect(fx.isEmpty)

    let (later, more) = run([.voice(.ready), .speakDown(selection: "")], from: w)
    #expect(later.mode == .listening(Draft(quote: "sel"), partial: "", save: false))
    #expect(more == [.micStart(take: 1)])
}

@Test func voiceModeComesFromConfig() {
    #expect(parseConfig("[voice]\nmode = \"tap\"").voice == .tap)
    #expect(parseConfig("[voice]\nmode = \"toggle\"").problems.count == 1)
}

@Test func staleSpeechResultsAreIgnored() {
    let (w, fx) = run([
        .speakDown(selection: ""), .cancel,          // take 1 cancelled
        .speakDown(selection: ""),                   // take 2
        .partial(take: 1, "old"), .final(take: 1, "old"),
        .final(take: 2, "new"),
    ])
    #expect(w.stacks[0] == [Note(quote: "", body: "new")])
    #expect(fx == [.micStart(take: 1), .micCancel, .micStart(take: 2), .save])
}

@Test func resultsAfterCancelDoNothing() {
    let (w, _) = run([.speakDown(selection: ""), .cancel, .final(take: 1, "late")])
    #expect(w.mode == .idle)
    #expect(w.stacks.joined().isEmpty)
}

@Test func invalidTransitionsAreNoOps() {
    let start = World()
    for e: Event in [.commit, .cancel, .edit("x"), .speakUp, .final(take: 0, "x"), .select(9), .select(-1), .paste] {
        let (w, fx) = run([e], from: start)
        #expect(w == start, "\(e)")
        #expect(fx.isEmpty, "\(e)")
    }
}

@Test func editsAreIgnoredWhileListening() {
    let (w, _) = run([.speakDown(selection: ""), .edit("x"), .commit])
    #expect(w.mode == .listening(Draft(quote: ""), partial: "", save: true))
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

// MARK: Config

@Test func defaultConfigFileParsesToTheBuiltInDefaults() {
    #expect(parseConfig(defaultConfigText) == Config())
}

@Test func configReadsKeysNamesAndCard() {
    let c = parseConfig("""
    [keys]
    note = "ctrl+shift+n"   # comment
    paste = ""
    [stacks]
    2 = "Papers # to read"
    [card]
    lines = 99
    opacity = 0.5
    """)
    #expect(c.keys[Action.note.rawValue] == Shortcut(code: 45, mods: modCtrl | modShift))
    #expect(c.keys[Action.paste.rawValue] == nil)
    #expect(c.names[1] == "Papers # to read")
    #expect(c.lines == 12)
    #expect(c.opacity == 0.5)
    #expect(c.problems.isEmpty)
}

@Test func configReportsMistakesAndKeepsDefaults() {
    let c = parseConfig("""
    stray = 1
    [keys]
    note = "g"
    speak = "cmd+banana"
    nope = "cmd+x"
    [stacks]
    5 = "too many"
    [card]
    lines = lots
    """)
    #expect(c.keys == Config().keys)
    #expect(c.problems.count == 6)
}

@Test func duplicateShortcutTurnsTheLaterActionOff() {
    let c = parseConfig("[keys]\nopen = \"cmd+g\"")
    #expect(c.keys[Action.note.rawValue] == Shortcut(code: 5, mods: modCmd))
    #expect(c.keys[Action.open.rawValue] == nil)
    #expect(c.problems.count == 1)
}

@Test func shortcutLabels() {
    #expect(shortcutLabel(parseShortcut("cmd+ctrl+v")!) == "⌃⌘V")
    #expect(shortcutLabel(parseShortcut("opt+space")!) == "⌥Space")
    #expect(parseShortcut("shift+a") == nil)
}

@Test func configureRebindsOnlyWhenKeysChange() {
    var names = Config()
    names.names[0] = "Inbox"
    let (w, fx) = run([.configure(names)])
    #expect(w.config.names[0] == "Inbox")
    #expect(fx.isEmpty)

    var keys = Config()
    keys.keys[0] = nil
    let (_, more) = run([.configure(keys)])
    #expect(more == [.bindKeys])
}

@Test func openShowsTheActiveStackWhenIdle() {
    #expect(run([.select(2), .open]).1 == [.save, .open(2)])
    #expect(run([.capture(selection: ""), .open]).1.isEmpty)
}

@Test func stackDocumentHasNameAndPasteBody() {
    #expect(stackDocument(name: "Ideas", notes: []) == "# Ideas\n\n_No notes yet._\n")
    #expect(stackDocument(name: "Ideas", notes: [Note(quote: "q", body: "b")]) == "# Ideas\n\n> q\n\nb\n")
}
