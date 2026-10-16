import AppKit
import Core

// The whole app loop: Event → step → render → effects.

let dataDir = URL.applicationSupportDirectory.appending(path: "Sendpoint")
let storeURL = dataDir.appending(path: "notes.json")
let configURL = URL(filePath: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? NSHomeDirectory() + "/.config")
    .appending(path: "sendpoint/config.toml")
var world = (try? Data(contentsOf: storeURL)).flatMap(Saved.decode) ?? World()

func send(_ event: Event) {
    let effects = step(&world, event)
    render()
    for effect in effects { perform(effect) }
}

func render() {
    panel.render(world, speechStatus: speech.status)
    menu.render(world, speechStatus: speech.status)
}

func perform(_ effect: Effect) {
    switch effect {
    case .micStart(let take): speech.start(take: take)
    case .micStop(let take): speech.stop(take: take)
    case .micCancel: speech.cancel()
    case .paste(let markdown): Selection.paste(markdown)
    case .save: save()
    case .open(let i):
        let url = stackURL(i)
        let doc = Data(stackDocument(name: world.config.names[i], notes: world.stacks[i]).utf8)
        diskQueue.async {
            write(doc, to: url)
            DispatchQueue.main.async { openFile(url) }
        }
    case .bindKeys:
        Keys.bind(world.config.keys)
        render()
    }
}

// MARK: Disk

let diskQueue = DispatchQueue(label: "app.sendpoint.disk", qos: .utility)

func stackURL(_ i: Int) -> URL { dataDir.appending(path: "stack-\(i + 1).md") }

/// notes.json is the truth; the stack-N.md files mirror it so an open editor stays current.
func save() {
    let json = Saved.encode(world)
    let docs = (0..<stackCount).map { Data(stackDocument(name: world.config.names[$0], notes: world.stacks[$0]).utf8) }
    let store = storeURL
    let urls = (0..<stackCount).map(stackURL)
    diskQueue.async {
        write(json, to: store)
        for i in docs.indices { write(docs[i], to: urls[i]) }
    }
}

nonisolated func write(_ data: Data, to url: URL) {
    if (try? Data(contentsOf: url)) == data { return }   // don't poke editors with no-op writes
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

/// The file's default app, or TextEdit when nothing claims .md / .toml.
func openFile(_ url: URL) {
    let app = NSWorkspace.shared.urlForApplication(toOpen: url)
        ?? URL(filePath: "/System/Applications/TextEdit.app")
    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
}

// MARK: Config

/// Polled once a second: a stat is nothing, and it catches every way an editor saves.
var configStamp: Date?

func pollConfig() {
    let stamp = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
    guard stamp != configStamp else { return }
    configStamp = stamp
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
        write(Data(defaultConfigText.utf8), to: configURL)   // first launch, or deleted: start from the defaults
        return
    }
    let config = parseConfig(text)
    if config != world.config { send(.configure(config)) }
}

// MARK: Keys → Events

func onKey(_ action: Action, down: Bool) {
    let idle = world.mode == .idle
    switch (action, down) {
    case (.note, true):
        send(.capture(selection: idle ? Selection.read(copyTimeout: 0.3) : ""))
    case (.speak, true):
        send(.speakDown(selection: idle ? Selection.read(copyTimeout: 0.15) : ""))
    case (.speak, false):
        send(.speakUp)
    case (.paste, true): send(.paste)
    case (.open, true): send(.open)
    case (.stack1, true): send(.select(0))
    case (.stack2, true): send(.select(1))
    case (.stack3, true): send(.select(2))
    case (.stack4, true): send(.select(3))
    default: break
    }
}

// MARK: Launch

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = Panel()
let menu = StatusMenu()
let speech = Speech()
Keys.install(onKey)
Keys.bind(world.config.keys)   // defaults; the first poll swaps in the file's keys if they differ
pollConfig()
pollConfig()   // picks up the defaults file the first call may have just written
RunLoop.main.add(Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { pollConfig() } }, forMode: .common)
_ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
speech.prewarm()
render()
app.run()
