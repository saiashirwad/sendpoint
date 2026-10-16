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

private func tapMode() -> World {
    var w = World()
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

// MARK: Settings window

@Test func settingAValueUpdatesConfigAndWritesItsLine() {
    let (w, fx) = run([.set(.lines(40)), .set(.opacity(0.9100000001)), .set(.voice(.tap))])
    #expect(w.config.lines == 12)
    #expect(w.config.opacity == 0.91)
    #expect(w.config.voice == .tap)
    #expect(fx == [.writeConfig(.lines(12)), .writeConfig(.opacity(0.91)), .writeConfig(.voice(.tap))])
    #expect(run([.set(.voice(.hold))]).1.isEmpty)   // already so: nothing to write
}

@Test func blankStackNameFallsBackToItsNumber() {
    let (w, fx) = run([.set(.name(2, "  \"\"  "))])
    #expect(w.config.names[2] == "Stack 3")
    #expect(fx == [.writeConfig(.name(2, "Stack 3"))])
}

@Test func recordingUnbindsUntilAShortcutLands() {
    let chord = Shortcut(code: 45, mods: modCmd | modShift)   // ⇧⌘N
    let (w, fx) = run([.record(.note), .record(.note), .set(.key(.note, chord))])
    #expect(w.recording == nil)
    #expect(w.config.keys[Action.note.rawValue] == chord)
    #expect(fx == [.bindKeys, .writeConfig(.key(.note, chord)), .bindKeys])
    #expect(run([.record(.note), .record(nil)]).1 == [.bindKeys, .bindKeys])
}

@Test func takenOrUnnamedChordsAreRefusedAndRecordingContinues() {
    let taken = Config().keys[Action.speak.rawValue]!
    let (w, fx) = run([.record(.note), .set(.key(.note, taken))])
    #expect(w.recording == .note)
    #expect(w.notice == Notice(action: .note, text: "⌘E is already Voice note."))
    #expect(w.config == Config())
    #expect(fx == [.bindKeys])

    let (bare, _) = run([.record(.note), .set(.key(.note, Shortcut(code: 0, mods: modShift)))])
    #expect(bare.recording == .note)
    #expect(bare.notice?.action == .note)

    let (off, more) = run([.record(.paste), .set(.key(.paste, nil))])
    #expect(off.config.keys[Action.paste.rawValue] == nil)
    #expect(off.notice == nil)
    #expect(more == [.bindKeys, .writeConfig(.key(.paste, nil)), .bindKeys])
}

@Test func editConfigRewritesOneLineAndKeepsComments() {
    let text = editConfig(defaultConfigText, .key(.note, Shortcut(code: 45, mods: modCtrl | modShift)))
    #expect(text.contains(#"note   = "ctrl+shift+n" # type a note about the selection"#))
    #expect(text.components(separatedBy: "\n").count == defaultConfigText.components(separatedBy: "\n").count)
    #expect(editConfig(defaultConfigText, .opacity(0.5)).contains("opacity   = 0.5    # 0.3 to 1"))
}

@Test func editConfigAddsMissingLinesAndSections() {
    #expect(editConfig("[card]\nlines = 3\n", .width(500)) == "[card]\nlines = 3\nwidth = 500\n")
    #expect(editConfig("# mine\n", .voice(.tap)) == "# mine\n\n[voice]\nmode = \"tap\"\n")
}

@Test func everySettingRoundTripsThroughTheFile() {
    let settings: [Setting] = [
        .key(.open, Shortcut(code: 122, mods: modCtrl | modOpt | modShift | modCmd)), .key(.stack4, nil),
        .voice(.tap), .name(1, "Papers # to read"), .lines(7), .fontSize(15.5), .opacity(0.65), .width(612),
    ]
    var w = World()
    var text = defaultConfigText
    for s in settings {
        for case .writeConfig(let written) in step(&w, .set(s)) { text = editConfig(text, written) }
    }
    #expect(parseConfig(text) == w.config)
}
