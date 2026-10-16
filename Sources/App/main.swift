import AppKit
import Core

// The whole app loop: Event → step → render → effects.

let storeURL = URL.applicationSupportDirectory.appending(path: "Sendpoint/notes.json")
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
    case .save: save(Saved.encode(world))
    }
}

let saveQueue = DispatchQueue(label: "app.sendpoint.save", qos: .utility)
func save(_ data: Data) {
    let url = storeURL
    saveQueue.async {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: Keys → Events

var speakDownAt = Date.distantPast

func onKey(_ key: Key, down: Bool) {
    let idle = world.mode == .idle
    switch (key, down) {
    case (.capture, true):
        send(.capture(selection: idle ? Selection.read(copyTimeout: 0.3) : ""))
    case (.speak, true):
        speakDownAt = Date()
        send(.speakDown(selection: idle ? Selection.read(copyTimeout: 0.15) : ""))
    case (.speak, false):
        send(.speakUp(tap: Date().timeIntervalSince(speakDownAt) < 0.3))
    case (.paste, true):
        send(.paste)
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
_ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
speech.prewarm()
render()
app.run()
