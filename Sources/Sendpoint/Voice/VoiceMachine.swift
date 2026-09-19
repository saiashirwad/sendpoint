import Foundation

nonisolated enum VoiceOutput: Equatable, Sendable {
    case started(UUID)
    case partial(UUID, String)
    case transcript(UUID, String)
    case failed(UUID, String)
}

nonisolated enum VoiceEvent: Equatable, Sendable {
    case warmUp
    case start(UUID, modelReady: Bool)
    case stop(UUID, now: Date)
    case discard
    case teardown
    case micStarted(UUID, Date)
    case micFailed(UUID, String)
    case transcribed(UUID, String)
    case transcriptionFailed(UUID, String)
    case settled
}

nonisolated enum VoiceEffect: Equatable, Sendable {
    case prepare
    case startMic(UUID)
    case stopMic
    case finish(UUID)
    case abandon
    case tearDown
    case emit(VoiceOutput)
}

nonisolated struct VoiceMachine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case starting(UUID)
        case recording(UUID, since: Date)
        case transcribing(UUID)
        case settling(next: UUID?)
        case tornDown
    }

    static let minimumClipDuration: TimeInterval = 0.3
    static let modelMissing = "Voice model is missing. Download it in Settings › Voice."

    private(set) var phase = Phase.idle

    var take: UUID? {
        switch phase {
        case let .starting(take), let .recording(take, _), let .transcribing(take): take
        case .idle, .settling, .tornDown: nil
        }
    }

    mutating func update(_ event: VoiceEvent) -> [VoiceEffect] {
        guard phase != .tornDown else { return [] }
        switch event {
        case .teardown:
            phase = .tornDown
            return [.stopMic, .tearDown]

        case .warmUp:
            return [.prepare]

        case let .start(take, modelReady):
            guard modelReady else { return [.emit(.failed(take, Self.modelMissing))] }
            switch phase {
            case .idle:
                phase = .starting(take)
                return [.startMic(take)]
            case .settling:
                phase = .settling(next: take)
                return []
            case .starting:
                phase = .starting(take)
                return [.stopMic, .startMic(take)]
            case .recording, .transcribing:
                let effects = discard()
                phase = .settling(next: take)
                return effects
            case .tornDown:
                return []
            }

        case let .micStarted(take, date):
            guard phase == .starting(take) else { return [] }
            phase = .recording(take, since: date)
            return [.emit(.started(take))]

        case let .micFailed(take, message):
            guard phase == .starting(take) else { return [] }
            phase = .idle
            return [.stopMic, .emit(.failed(take, message))]

        case let .stop(take, now):
            guard case .recording(take, let since) = phase else { return [] }
            guard now.timeIntervalSince(since) >= Self.minimumClipDuration else {
                phase = .settling(next: nil)
                return [.stopMic, .abandon, .prepare, .emit(.transcript(take, ""))]
            }
            phase = .transcribing(take)
            return [.stopMic, .finish(take), .prepare]

        case .discard:
            return discard()

        case let .transcribed(take, text):
            guard phase == .transcribing(take) else { return [] }
            phase = .idle
            return [.emit(.transcript(take, text))]

        case let .transcriptionFailed(take, message):
            guard phase == .transcribing(take) else { return [] }
            phase = .settling(next: nil)
            return [.abandon, .emit(.failed(take, message))]

        case .settled:
            guard case let .settling(next) = phase else { return [] }
            guard let next else {
                phase = .idle
                return []
            }
            phase = .starting(next)
            return [.startMic(next)]
        }
    }

    private mutating func discard() -> [VoiceEffect] {
        switch phase {
        case .idle, .tornDown:
            return []
        case .settling:
            phase = .settling(next: nil)
            return []
        case .starting:
            phase = .idle
            return [.stopMic]
        case .recording:
            phase = .settling(next: nil)
            return [.stopMic, .abandon, .prepare]
        case .transcribing:
            phase = .settling(next: nil)
            return [.abandon]
        }
    }
}
