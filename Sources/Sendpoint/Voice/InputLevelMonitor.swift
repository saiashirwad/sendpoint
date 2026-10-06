import Foundation
import Observation

@Observable
final class InputLevelMonitor {
    private enum Phase: Equatable {
        case stopped, starting(UUID), running, tornDown
    }
    private enum Event {
        case start(MicrophoneOrder), stop, started(UUID), unavailable(UUID), teardown
    }
    private enum Command {
        case start(UUID, MicrophoneOrder), stop
    }

    private var phase = Phase.stopped
    var isRunning: Bool { phase == .running }
    var level: Float { meter.current }

    @ObservationIgnored private let meter: VoiceLevelMeter
    @ObservationIgnored private let commands: AsyncStream<Command>.Continuation
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(meter: VoiceLevelMeter = VoiceLevelMeter(decay: 0.82),
         microphone: Microphone? = nil,
         isAuthorized: @escaping () -> Bool = { PermissionCheck.isMicrophoneAuthorized }) {
        self.meter = meter
        let microphone = microphone ?? .live(meter: meter)
        let (stream, commands) = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        self.commands = commands
        task = Task { [weak self] in
            for await command in stream {
                await microphone.stop()
                guard !Task.isCancelled else { break }
                if case let .start(id, order) = command, self?.phase == .starting(id) {
                    if isAuthorized() {
                        do {
                            try await microphone.start(order, nil)
                            if !Task.isCancelled { self?.send(.started(id)) }
                        } catch {
                            await microphone.stop()
                            self?.send(.unavailable(id))
                        }
                    } else { self?.send(.unavailable(id)) }
                }
                self?.completeCommand()
            }
            await microphone.stop()
            await microphone.teardown()
            self?.completeCommand(releasing: true)
        }
    }

    deinit {
        commands.finish()
        task?.cancel()
    }

    func start(_ order: MicrophoneOrder) { send(.start(order)) }
    func stop() { send(.stop) }
    func teardown() { send(.teardown) }

    func waitUntilSettled() async {
        if phase == .tornDown { await task?.value }
        else if pending > 0 { await withCheckedContinuation { waiters.append($0) } }
    }

    private func send(_ event: Event) {
        guard phase != .tornDown else { return }
        let command: Command
        switch event {
        case let .start(order):
            let id = UUID()
            phase = .starting(id)
            command = .start(id, order)
        case .stop:
            phase = .stopped
            command = .stop
        case .teardown:
            phase = .tornDown
            meter.reset()
            commands.finish()
            task?.cancel()
            return
        case let .started(id):
            guard phase == .starting(id) else { return }
            phase = .running
            return
        case let .unavailable(id):
            guard phase == .starting(id) else { return }
            phase = .stopped
            return
        }
        meter.reset()
        pending += 1
        commands.yield(command)
    }

    private func completeCommand(releasing: Bool = false) {
        pending = releasing ? 0 : pending - 1
        guard pending == 0 else { return }
        let ready = waiters
        waiters.removeAll()
        ready.forEach { $0.resume() }
    }
}
