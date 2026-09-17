import AudioToolbox
import AVFoundation
import Foundation
import Observation

@Observable
final class InputLevelMonitor {
    private(set) var level: Float = 0
    var isRunning: Bool { engine != nil }

    private var engine: AVAudioEngine?
    private var meterTask: Task<Void, Never>?
    private var tapContinuation: AsyncStream<Float>.Continuation?
    private var tapEpoch = 0

    func start(preferredUID: String?) {
        stop()
        guard PermissionCheck.isMicrophoneAuthorized else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let device = InputDeviceChoice.resolve(
            preferredUID: preferredUID,
            available: AudioInputDeviceQuery.allInputs()
        ) {
            _ = AudioInputDeviceQuery.select(device, on: input)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        tapEpoch += 1
        let epoch = tapEpoch
        let (levels, continuation) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        tapContinuation = continuation
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable [continuation] buffer, _ in
            continuation.yield(VoiceLevelMeter.level(of: buffer))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapContinuation?.finish()
            tapContinuation = nil
            Diag.log("input level monitor failed to start: \(error.localizedDescription)")
            return
        }
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            for await sample in levels {
                guard !Task.isCancelled, let self, self.tapEpoch == epoch else { return }
                self.level = max(sample, self.level * 0.82)
            }
        }
        self.engine = engine
    }

    func stop() {
        tapEpoch += 1
        meterTask?.cancel()
        meterTask = nil
        tapContinuation?.finish()
        tapContinuation = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        level = 0
    }
}

final class MicrophonePreviewOwner {
    struct Engine {
        var start: (String?) async -> Void
        var stop: () -> Void
        var isRunning: () -> Bool
        var level: () -> Float

        static func live(_ monitor: InputLevelMonitor) -> Engine {
            Engine(
                start: { monitor.start(preferredUID: $0) },
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

    func start(uid: String?) {
        generation += 1
        let active = generation
        let previous = task
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, active == self.generation else { return }
            self.engine.stop()
            await self.engine.start(uid)
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
