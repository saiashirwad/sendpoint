import Foundation
import Observation

@Observable
final class InputLevelMonitor {
    private(set) var isRunning = false
    var level: Float { meter.current }

    @ObservationIgnored private let meter: VoiceLevelMeter
    @ObservationIgnored private let microphone: Microphone
    @ObservationIgnored private let isAuthorized: () -> Bool
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(meter: VoiceLevelMeter = VoiceLevelMeter(decay: 0.82),
         microphone: Microphone? = nil,
         isAuthorized: @escaping () -> Bool = { PermissionCheck.isMicrophoneAuthorized }) {
        self.meter = meter
        self.microphone = microphone ?? .live(meter: meter, collectFrames: false)
        self.isAuthorized = isAuthorized
    }

    func start(_ order: MicrophoneOrder) async {
        generation += 1
        let current = generation
        scheduleStop()
        await stopTask?.value
        guard !Task.isCancelled, current == generation,
              isAuthorized() else { return }
        do {
            _ = try await microphone.start(order)
            guard !Task.isCancelled, current == generation else {
                await microphone.stop()
                return
            }
            isRunning = true
        } catch {
            guard !Task.isCancelled, current == generation else { return }
            Diag.log("input level monitor failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        generation += 1
        scheduleStop()
    }

    private func scheduleStop() {
        isRunning = false
        meter.reset()
        let previous = stopTask
        let current = generation
        stopTask = Task { [weak self, microphone] in
            await previous?.value
            await microphone.stop()
            guard let self, self.generation == current else { return }
            self.stopTask = nil
        }
    }
}

final class MicrophonePreviewOwner {
    struct Engine {
        var start: (MicrophoneOrder) async -> Void
        var stop: () -> Void
        var isRunning: () -> Bool
        var level: () -> Float

        static func live(_ monitor: InputLevelMonitor) -> Engine {
            Engine(
                start: { await monitor.start($0) },
                stop: { monitor.stop() },
                isRunning: { monitor.isRunning },
                level: { monitor.level }
            )
        }
    }

    private let engine: Engine
    private var task: Task<Void, Never>?
    private var generation = 0

    var level: Float { engine.level() }
    var isActive: Bool { engine.isRunning() }

    init(engine: Engine) {
        self.engine = engine
    }

    convenience init(monitor: InputLevelMonitor = InputLevelMonitor()) {
        self.init(engine: .live(monitor))
    }

    func start(_ order: MicrophoneOrder) {
        generation += 1
        let active = generation
        let previous = task
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, active == self.generation else { return }
            self.engine.stop()
            await self.engine.start(order)
            guard !Task.isCancelled, active == self.generation else {
                self.engine.stop()
                return
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        engine.stop()
    }
}
