import AudioToolbox
import AVFoundation
import Foundation
import Observation

/// Live loudness of the chosen microphone, for the level meter on the Voice
/// tab. Runs only while that tab is on screen; nothing is written anywhere.
@Observable
final class InputLevelMonitor {
    /// 0…1 on the same speech-centred scale as `VoiceLevelMeter`.
    private(set) var level: Float = 0
    var isRunning: Bool { engine != nil }

    private var engine: AVAudioEngine?
    /// Retained consumer for the live tap's levels; cancelled on every stop
    /// path. One owner, never detached.
    private var meterTask: Task<Void, Never>?
    /// Yield end of the tap-level stream. The tap holds its own copy, so the
    /// realtime thread never touches actor state.
    private var tapContinuation: AsyncStream<Float>.Continuation?
    /// Delivery generation. Bumped on every start and stop; levels presented
    /// with an older epoch are stale and dropped, so a late flush cannot
    /// raise `level` after `stop()` zeroed it.
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

        // Latest-value coalescing, mirroring VoiceNoteService: the tap
        // captures only a Sendable continuation (realtime-safe, never blocks,
        // no hop of its own); `.bufferingNewest(1)` keeps only the newest
        // level when the consumer lags. This replaces the old unordered
        // per-tap `Task { @MainActor }` fan-out with one ordered stream whose
        // deliveries are dropped once their epoch goes stale.
        // The tap runs off the main thread; it must not inherit this method's isolation.
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
                // Rise instantly, fall gently, like the system meter.
                self.level = max(sample, self.level * 0.82)
            }
        }
        self.engine = engine
    }

    func stop() {
        // Invalidate first: levels already yielded but not yet delivered go
        // stale, so they cannot raise `level` after it is zeroed below.
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

/// Owns the Settings mic-preview lifecycle: one retained start task, one
/// engine, one stop path. The capture pane calls start/stop from explicit
/// appear/disappear/change callbacks; mic changes restart explicitly, never
/// through a task-id key. Bring-ups run serialized in the retained task
/// chain (never inline on the render path, as with the old `.task`), so two
/// engines never overlap: a superseded start exits before touching the
/// engine, and one that loses the race mid-bring-up tears its stale engine
/// down via the generation check, mirroring LocalStreamingPreview.
final class MicrophonePreviewOwner {
    /// The engine behind the preview. A struct of closures so tests prove
    /// cancellation and stale-start cleanup without microphone hardware.
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

    /// Starts previewing `uid`, superseding any in-flight start.
    func start(uid: String?) {
        generation += 1
        let active = generation
        let previous = task
        task?.cancel()
        task = Task { @MainActor [weak self] in
            // Serialize bring-ups: a newer start waits for the older one to
            // finish or cancel, so the old engine is gone before the new
            // one starts.
            await previous?.value
            guard let self, !Task.isCancelled, active == self.generation else { return }
            self.engine.stop()
            await self.engine.start(uid)
            guard !Task.isCancelled, active == self.generation else {
                // Superseded mid-bring-up: never leave a stale tap behind.
                self.engine.stop()
                return
            }
        }
    }

    /// The single teardown path. Synchronous and idempotent: cancels any
    /// in-flight bring-up and stops the engine. A bring-up that resumes
    /// afterwards sees the generation mismatch and cleans up after itself.
    func stop() {
        generation += 1
        task?.cancel()
        engine.stop()
    }
}
