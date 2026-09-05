/// A preference, not a gesture inferred from how long the keys stay down.
enum VoiceRecordingMode: String, CaseIterable, Sendable {
    case hold
    case tap

    var title: String { self == .hold ? "Hold" : "Tap" }
    var detail: String {
        switch self {
        case .hold: "Hold to speak, then release to save to the stack."
        case .tap: "Press once to speak, then press again to save to the stack."
        }
    }
}

enum VoiceTriggerEvent: Equatable {
    case pressed
    case released
    case menuToggle
    case escape
    case captureEnded
    case configurationChanged(VoiceRecordingMode)
}

enum VoiceTriggerCommand: Equatable {
    case beginCapture
    case finishCapture
    case cancelCapture
}

/// Tracks physical key release separately from capture completion so repeats,
/// cancellation, and synchronous startup failures cannot retrigger recording.
struct VoiceTriggerMachine: Equatable {
    enum State: Equatable {
        case idle
        case held
        case recording
        case awaitingRelease
    }

    private(set) var state: State = .idle
    private(set) var mode: VoiceRecordingMode = .hold

    mutating func handle(_ event: VoiceTriggerEvent) -> [VoiceTriggerCommand] {
        switch event {
        case .pressed:
            switch state {
            case .idle:
                state = .held
                return [.beginCapture]
            case .recording:
                state = .awaitingRelease
                return [.finishCapture]
            case .held, .awaitingRelease:
                return []
            }
        case .released:
            switch state {
            case .held:
                state = mode == .hold ? .idle : .recording
                return mode == .hold ? [.finishCapture] : []
            case .awaitingRelease:
                state = .idle
            case .idle, .recording:
                break
            }
        case .menuToggle:
            switch state {
            case .idle:
                state = .recording
                return [.beginCapture]
            case .recording:
                state = .idle
                return [.finishCapture]
            case .held, .awaitingRelease:
                break
            }
        case .escape:
            switch state {
            case .held:
                state = .awaitingRelease
                return [.cancelCapture]
            case .recording:
                state = .idle
                return [.cancelCapture]
            case .idle, .awaitingRelease:
                break
            }
        case .captureEnded:
            switch state {
            case .held: state = .awaitingRelease
            case .recording: state = .idle
            case .idle, .awaitingRelease: break
            }
        case let .configurationChanged(mode):
            let wasRecording = state == .held || state == .recording
            state = .idle
            self.mode = mode
            return wasRecording ? [.cancelCapture] : []
        }
        return []
    }
}
