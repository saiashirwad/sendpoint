import Foundation
import Observation
import SendpointDomain

@MainActor
@Observable
final class SetupTour {
    enum Step: Int, CaseIterable, Equatable {
        case voice
        case text
        case send

        static let railNames = allCases.map(\.label)

        var label: String {
            switch self {
            case .voice: "Voice note"
            case .text: "Typed note"
            case .send: "Send"
            }
        }

        var headline: String {
            switch self {
            case .voice: "Say something about this"
            case .text: "Now type one"
            case .send: "Now send them"
            }
        }

        func detail(keys: SetupTourKeys, voiceMode: VoiceRecordingMode) -> String {
            switch self {
            case .voice:
                switch voiceMode {
                case .hold: "Select the line below, hold \(keys.voice), speak, let go."
                case .tap: "Select the line below, press \(keys.voice), speak, press it again."
                }
            case .text:
                "Select the line below, press \(keys.capture), type, then ⌘↩."
            case .send:
                "\(keys.copy) puts your notes into any chat, at the cursor."
            }
        }

        var passage: String? {
            switch self {
            case .voice:
                "Say a thought out loud while you read, and the passage you "
                    + "selected is quoted under it, word for word."
            case .text:
                "Type a thought instead when you would rather not speak. "
                    + "The same quote is kept under it."
            case .send:
                nil
            }
        }

        func tip(keys: SetupTourKeys) -> String? {
            guard self == .send else { return nil }
            let show = "\(keys.stack) shows the current stack."
            return keys.stacks.isEmpty ? show : "\(keys.stacks) switch between five stacks.\n\(show)"
        }
    }

    enum Event {
        case presented
        case noteCount(Int)
        case skip
    }

    private(set) var step: Step = .voice
    private var seenNotes: Int?

    func send(_ event: Event) {
        switch event {
        case .presented:
            seenNotes = nil
        case let .noteCount(count):
            if let seen = seenNotes, count > seen { advance() }
            seenNotes = count
        case .skip:
            advance()
        }
    }

    private func advance() {
        switch step {
        case .voice: step = .text
        case .text, .send: step = .send
        }
    }

    static func noteCount(in store: StackStore) -> Int {
        store.stacks.reduce(0) { $0 + $1.notes.count }
    }
}

struct SetupTourKeys: Equatable {
    let voice: String
    let capture: String
    let stack: String
    let copy: String
    let stacks: String

    init(voice: String, capture: String, stack: String, copy: String, stacks: String) {
        self.voice = voice
        self.capture = capture
        self.stack = stack
        self.copy = copy
        self.stacks = stacks
    }

    @MainActor
    init(shortcuts: ShortcutSettings) {
        self.init(
            voice: shortcuts.voiceCaptureCombo.displayString,
            capture: shortcuts.captureCombo.displayString,
            stack: shortcuts.stackCombo.displayString,
            copy: shortcuts.copyCombo.displayString,
            stacks: (1...StackDocument.stackCount)
                .compactMap { shortcuts.selectStackCombo($0)?.displayString }
                .joined(separator: " ")
        )
    }
}
