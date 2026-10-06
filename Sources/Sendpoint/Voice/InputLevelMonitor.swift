import Foundation
import Observation

@Observable
final class InputLevelMonitor {
    private enum Phase: Equatable {
        case stopped, starting(UUID), running, tornDown
    }
    private enum Event {
        case start(MicrophoneOrder), stop, started(UUID), teardown
    }

    private var phase = Phase.stopped
    var isRunning: Bool { phase == .running }
    var level: Float { meter.current }

    @ObservationIgnored private let meter: VoiceLevelMeter
    @ObservationIgnored private let microphone: Microphone
    @ObservationIgnored private let isAuthorized: () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?

    init(meter: VoiceLevelMeter = VoiceLevelMeter(decay: 0.82),
         microphone: Microphone? = nil,
         isAuthorized: @escaping () -> Bool = { PermissionCheck.isMicrophoneAuthorized }) {
        self.meter = meter
        self.microphone = microphone ?? .live(meter: meter, collectFrames: false)
        self.isAuthorized = isAuthorized
    }

    func start(_ order: MicrophoneOrder) { send(.start(order)) }
    func stop() { send(.stop) }
    func teardown() { send(.teardown) }
    func waitUntilSettled() async { await task?.value }

    private func send(_ event: Event) {
        guard phase != .tornDown else { return }
        let next: (UUID, MicrophoneOrder)?
        switch event {
        case let .start(order):
            let id = UUID()
            phase = .starting(id)
            next = (id, order)
        case .stop:
            phase = .stopped
            next = nil
        case .teardown:
            phase = .tornDown
            next = nil
        case let .started(id):
            guard phase == .starting(id) else { return }
            phase = .running
            return
        }
        meter.reset()
        let previous = task
        previous?.cancel()
        let terminating = phase == .tornDown
        task = Task { [weak self, microphone] in
            await previous?.value
            await microphone.stop()
            if terminating {
                await microphone.teardown()
                return
            }
            guard let (id, order) = next, !Task.isCancelled,
                  let self, self.phase == .starting(id), self.isAuthorized() else { return }
            do {
                _ = try await microphone.start(order)
                guard !Task.isCancelled, self.phase == .starting(id) else { return }
                self.send(.started(id))
            } catch {
                guard !Task.isCancelled, self.phase == .starting(id) else { return }
                self.send(.stop)
            }
        }
    }
}
