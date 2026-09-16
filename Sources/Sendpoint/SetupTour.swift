import Foundation
import Observation
import SendpointDomain

/// The three things to try once every permission is in: a spoken note, a
/// typed one, then the stack they landed in, with a word on the way out.
/// Each slide waits for a real note to arrive before moving on, or a skip.
@MainActor
@Observable
final class SetupTour {
    enum Step: Int, CaseIterable, Equatable {
        case voice
        case text
        case stack
        case done

        /// The rail names the three things to do; the last slide ticks them all.
        static let railNames = [Step.voice, .text, .stack].map(\.label)

        var label: String {
            switch self {
            case .voice: "Voice note"
            case .text: "Typed note"
            case .stack: "Stack"
            case .done: "Done"
            }
        }

        var headline: String {
            switch self {
            case .voice: "Say something about this"
            case .text: "Now type one"
            case .stack: "They're in your stack"
            case .done: "Enjoy Sendpoint"
            }
        }

        /// One line, naming the user's own shortcuts.
        func detail(keys: SetupTourKeys, voiceMode: VoiceRecordingMode) -> String {
            switch self {
            case .voice:
                switch voiceMode {
                case .hold: "Select the line below, hold \(keys.voice), speak, let go."
                case .tap: "Select the line below, press \(keys.voice), speak, press it again."
                }
            case .text:
                "Select the line below, press \(keys.capture), type, then ⌘↩."
            case .stack:
                "\(keys.stack) opens it any time. \(keys.copy) copies everything."
            case .done:
                "It lives in the menu bar. Settings are there too."
            }
        }

        var showsPassage: Bool { self == .voice || self == .text }
    }

    enum Event {
        /// Every note across every stack, sampled by whoever owns the store.
        case noteCount(Int)
        case skip
        /// The stack is on screen; setup waits behind it with the last word.
        case openedStack
    }

    /// Something to select. Two lines at the setup window's width.
    static let passage =
        "Sendpoint keeps each note you make while reading, in order, "
        + "so a whole train of thought can be sent as one prompt."

    private(set) var step: Step = .voice
    private var seenNotes: Int?

    func send(_ event: Event) {
        switch event {
        case let .noteCount(count):
            // The first sample is the baseline, whenever the store arrives.
            // Only the two note slides wait on a note.
            if let seen = seenNotes, count > seen, step == .voice || step == .text { advance() }
            seenNotes = count
        case .skip:
            advance()
        case .openedStack:
            if step == .stack { step = .done }
        }
    }

    private func advance() {
        switch step {
        case .voice: step = .text
        case .text: step = .stack
        case .stack: step = .done
        case .done: break
        }
    }

    static func noteCount(in store: StackStore) -> Int {
        store.stacks.reduce(0) { $0 + $1.notes.count }
    }
}

/// The shortcuts a slide names, already formatted for reading.
struct SetupTourKeys: Equatable {
    let voice: String
    let capture: String
    let stack: String
    let copy: String

    init(voice: String, capture: String, stack: String, copy: String) {
        self.voice = voice
        self.capture = capture
        self.stack = stack
        self.copy = copy
    }

    @MainActor
    init(shortcuts: ShortcutSettings) {
        self.init(
            voice: shortcuts.voiceCaptureCombo.displayString,
            capture: shortcuts.captureCombo.displayString,
            stack: shortcuts.stackCombo.displayString,
            copy: shortcuts.copyCombo.displayString
        )
    }
}
