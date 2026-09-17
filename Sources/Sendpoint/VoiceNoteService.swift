import AVFoundation
import FluidAudio
import Foundation
import SendpointDomain

extension Notification.Name {
    static let voiceModelDidBecomeReady = Notification.Name("Sendpoint.voiceModelDidBecomeReady")
}

/// On-disk Parakeet Unified 0.6B streaming (320ms look-ahead). Setup, Settings,
/// and the recogniser all use this one tree.
nonisolated enum LocalVoiceModelFiles {
    static let streaming = UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2)

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    static var requiredFileNames: [String] {
        [
            ModelNames.ParakeetUnified.streamingEncoderFile(
                precision: .int8,
                contextSuffix: streaming.contextSuffix
            ),
            ModelNames.ParakeetUnified.decoderFile,
            ModelNames.ParakeetUnified.jointDecisionFile,
            ModelNames.ParakeetUnified.vocab,
        ]
    }

    static func exist() -> Bool {
        requiredFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent($0).path)
        }
    }
}

/// Records from the microphone and transcribes with Parakeet Unified 0.6B
/// streaming. The same decoder drives the live card and the saved note.
/// Nothing leaves the Mac.
///
/// Isolation: explicitly `@MainActor`. (The target's default isolation
/// already implied this; the annotation locks it in.) Every caller is
/// MainActor-bound — `CaptureController`'s `@MainActor` launch operations
/// and UI callbacks, plus `PermissionServices`' async hops — so serializing
/// all mutable state (`engine`/`spareEngine`/`audioQueue`/`streamTask`/
/// `warmUpTask`/`abandonment`/`streamGeneration`/`recordingStartedAt`, the
/// meter, `recordingEpoch`) on the MainActor removes the cross-task races
/// with no locks. An actor was rejected: the service is driven through
/// synchronous test-seam closures (`discard`, `warmUp`, device/partial
/// setters) that cannot await, so actor isolation would force signature
/// churn for no gain. The one closure that truly leaves the actor — the
/// realtime audio tap — captures only `Sendable` values (the frame queue and
/// an `AsyncStream` continuation) and re-enters via the ordered,
/// epoch-guarded meter pump below; it never blocks the tap thread.
@MainActor
final class VoiceNoteService {
    private let transcriber = LocalStreamingPreview()
    let levelMeter = VoiceLevelMeter()
    private var engine: AVAudioEngine?
    private var spareEngine: AVAudioEngine?
    private var audioQueue: PreviewAudioQueue?
    private var streamTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    /// Retained consumer for the live recording's tap levels; cancelled on
    /// every stop path. One owner, never detached.
    private var meterTask: Task<Void, Never>?
    /// Yield end of the tap-level stream. The tap holds its own copy, so the
    /// realtime thread never touches actor state.
    private var tapContinuation: AsyncStream<Float>.Continuation?
    private var abandonment: (id: UUID, task: Task<Void, Never>)?
    private var streamGeneration: Int?
    private var recordingStartedAt: Date?
    private(set) var recordingEpoch = 0
    /// Current recording generation. Bumped on every start and every stop
    /// path; tap levels and pump writes presented with an older epoch are
    /// stale and dropped, so a late flush can never corrupt post-stop state.

    /// UID of the microphone to record from; `nil` follows the system default.
    /// If the device is not connected when recording starts, the default is used.
    var preferredInputDeviceUID: String?
    /// Set once by the capture controller; receives cumulative hypotheses.
    var onPartialTranscript: (@Sendable (String) -> Void)?

    init() {}

    var isRecording: Bool { engine?.isRunning == true }

    func downloadVoiceModel(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try await transcriber.prepare(onProgress: onProgress)
    }

    func requestMicrophoneAccess() async -> Bool {
        switch PermissionCheck.microphonePermissionState {
        case .granted:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { @Sendable allowed in
                    continuation.resume(returning: allowed)
                }
            }
        case .denied, .restricted:
            return false
        }
    }

    /// Call once at launch and after every recording, when nobody is waiting.
    /// MainActor-serialized, so the `warmUpTask == nil` check-and-set is
    /// atomic — no second caller can interleave between the check and the
    /// assignment, and the completion write-back runs on the same actor.
    /// No generation counter needed.
    func warmUp() {
        if spareEngine == nil, PermissionCheck.isMicrophoneAuthorized {
            let engine = AVAudioEngine()
            _ = engine.inputNode
            spareEngine = engine
        }
        guard warmUpTask == nil else { return }
        let transcriber = transcriber
        warmUpTask = Task { [weak self] in
            await transcriber.prepareIfNeeded()
            self?.warmUpTask = nil
        }
    }

    func startRecording() async throws {
        await finishPendingAbandonment()
        try Task.checkCancellation()
        guard !isRecording else { return }

        let engine = spareEngine ?? AVAudioEngine()
        spareEngine = nil
        let input = engine.inputNode
        selectInputDevice(on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceNoteError.noInputDevice
        }

        let meter = levelMeter
        meter.reset()
        let queue = PreviewAudioQueue()
        audioQueue = queue
        // A new recording opens a new delivery generation: taps or pump
        // iterations left over from an older recording go stale on arrival.
        recordingEpoch += 1
        let epoch = recordingEpoch
        // Latest-value coalescing for the level meter. The tap captures only
        // Sendable values (the frame queue, the continuation), so the
        // realtime thread never blocks and schedules no hop of its own;
        // `.bufferingNewest(1)` keeps only the newest level when the consumer
        // lags, replacing the old unordered per-tap `Task { @MainActor }`
        // fan-out (~40/s) with one ordered stream.
        let (levels, continuation) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        tapContinuation = continuation
        Diag.log("voice tap format: \(format.sampleRate)Hz ch=\(format.channelCount) interleaved=\(format.isInterleaved)")
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { @Sendable [continuation] buffer, _ in
            if let frame = PreviewAudioFrame(buffer: buffer) {
                queue.append(frame)
            }
            continuation.yield(VoiceLevelMeter.level(of: buffer))
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioQueue = nil
            tapContinuation?.finish()
            tapContinuation = nil
            throw error
        }

        self.engine = engine
        recordingStartedAt = Date()
        startMeterPump(levels, epoch: epoch)
        startStreamPump(queue)
        Diag.log("voice recording started")
    }

    /// Points the input unit at the chosen microphone before the engine
    /// reads its format. Must run before anything else touches the node.
    ///
    /// The unit is always pinned to a concrete device. Left to follow the
    /// system default on its own, the input unit takes around half a second
    /// to start; pinned to that same default device it starts in about 50ms.
    private func selectInputDevice(on input: AVAudioInputNode) {
        let device = InputDeviceChoice.resolve(
            preferredUID: preferredInputDeviceUID,
            available: AudioInputDeviceQuery.allInputs()
        ) ?? AudioInputDeviceQuery.defaultInput()
        guard let device else { return }
        if AudioInputDeviceQuery.select(device, on: input) {
            Diag.log("voice input device: \(device.name)")
        }
    }

    static let minimumClipDuration: TimeInterval = 0.3

    func stopAndTranscribe() async throws -> String {
        try Task.checkCancellation()
        let duration = try stopMicrophone()
        let leftover = await stopStreamPump()
        guard duration >= Self.minimumClipDuration else {
            await transcriber.abandon()
            Diag.log("voice clip too short to hold speech; treating as silence")
            return ""
        }
        try Task.checkCancellation()
        Diag.log("voice transcription finishing")
        let generation = streamGeneration
        streamGeneration = nil
        let transcript = try await transcriber.finish(leftover: leftover, generation: generation)
        try Task.checkCancellation()
        return transcript.nonblank ?? ""
    }

    func discardRecording() {
        let wasLive = isRecording || recordingStartedAt != nil || streamTask != nil
        _ = try? stopMicrophone()
        invalidateTapDelivery()
        let pump = streamTask
        pump?.cancel()
        streamTask = nil
        audioQueue = nil
        streamGeneration = nil
        let previous = abandonment?.task
        let transcriber = transcriber
        let id = UUID()
        let task = Task {
            await pump?.value
            await previous?.value
            await transcriber.abandon()
        }
        abandonment = (id, task)
        if wasLive { Diag.log("voice recording discarded") }
    }

    /// Ends meter delivery for the current recording. The epoch bump comes
    /// first, so levels already yielded but not yet delivered go stale and
    /// cannot undo the reset below or leak into the next recording.
    /// Idempotent; safe on every stop path, live or not.
    private func invalidateTapDelivery() {
        recordingEpoch += 1
        meterTask?.cancel()
        meterTask = nil
        tapContinuation?.finish()
        tapContinuation = nil
    }

    /// Applies one delivered tap level iff `epoch` is still the live
    /// recording. Internal as a deterministic test seam for the
    /// stale-delivery guard (no microphone needed).
    func applyTapLevel(_ level: Float, epoch: Int) {
        guard epoch == recordingEpoch else { return }
        levelMeter.push(level)
    }

    /// The single retained consumer for the live recording's tap levels. One
    /// owner, never detached; cancelled by `invalidateTapDelivery`. Values
    /// apply in yield order; `AsyncStream` termination or task cancellation
    /// ends the loop, and the epoch check drops anything yielded before a
    /// stop that only gets delivered after it.
    private func startMeterPump(_ levels: AsyncStream<Float>, epoch: Int) {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            for await level in levels {
                guard !Task.isCancelled else { return }
                guard let self, self.recordingEpoch == epoch else { return }
                self.applyTapLevel(level, epoch: epoch)
            }
        }
    }

    /// Records the pump's generation only while its queue is still the live
    /// one. A pump cancelled by stop/discard/restart must not revive a
    /// generation after teardown cleared it: stop and discard nil the queue
    /// synchronously on this actor, and a restart installs a new queue, so
    /// identity precisely marks the write stale.
    private func applyStreamGeneration(_ generation: Int, for queue: PreviewAudioQueue) {
        guard audioQueue === queue else { return }
        streamGeneration = generation
    }

    /// A discarded stream must finish invalidating and resetting its decoder
    /// before a later recording is allowed to open one.
    private func finishPendingAbandonment() async {
        while let pending = abandonment {
            await pending.task.value
            if abandonment?.id == pending.id {
                abandonment = nil
            }
        }
    }

    private func startStreamPump(_ queue: PreviewAudioQueue) {
        let handler = onPartialTranscript
        let transcriber = transcriber
        streamTask?.cancel()
        streamTask = Task {
            var generation: Int?
            while !Task.isCancelled, generation == nil {
                generation = await transcriber.begin(onPartial: { handler?($0) })
                if generation == nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard let generation, !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.applyStreamGeneration(generation, for: queue) }
            while !Task.isCancelled {
                let frames = queue.drain()
                if frames.isEmpty {
                    try? await Task.sleep(for: .milliseconds(5))
                    continue
                }
                await transcriber.feed(frames, generation: generation)
            }
        }
    }

    private func stopStreamPump() async -> [PreviewAudioFrame] {
        streamTask?.cancel()
        await streamTask?.value
        streamTask = nil
        let leftover = audioQueue?.drain() ?? []
        audioQueue = nil
        return leftover
    }

    private func stopMicrophone() throws -> TimeInterval {
        guard let engine else { throw VoiceNoteError.noActiveRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        invalidateTapDelivery()
        levelMeter.reset()
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        Diag.log("voice recording stopped, \(Int(duration * 1000))ms")
        warmUp()
        return duration
    }
}

private enum VoiceNoteError: LocalizedError {
    case noInputDevice
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .noActiveRecording:
            return "Voice recording did not start."
        }
    }
}

/// Fan-out for model preparation progress. Preparation is shared, so the
/// caller that started it is not always the one watching: launch warm-up
/// begins the download, then Setup asks to see it. Whoever subscribes gets
/// the latest fraction at once and every one after.
nonisolated final class VoiceModelProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [Int: @Sendable (Double) -> Void] = [:]
    private var nextID = 0
    private var latest: Double?

    /// Registers `observer`, replaying the latest fraction if one exists.
    /// Returns a token for `unsubscribe`.
    @discardableResult
    func subscribe(_ observer: @escaping @Sendable (Double) -> Void) -> Int {
        lock.lock()
        nextID += 1
        let id = nextID
        observers[id] = observer
        let replay = latest
        lock.unlock()
        if let replay { observer(replay) }
        return id
    }

    func unsubscribe(_ id: Int) {
        lock.lock()
        observers[id] = nil
        lock.unlock()
    }

    func report(_ fraction: Double) {
        lock.lock()
        latest = fraction
        let current = Array(observers.values)
        lock.unlock()
        for observer in current { observer(fraction) }
    }

    /// A new attempt starts from nothing; a stale fraction must not replay.
    func reset() {
        lock.lock()
        latest = nil
        lock.unlock()
    }
}

/// Parakeet Unified 0.6B streaming (320ms tier). One decoder for the card and the note.
actor LocalStreamingPreview {
    private let preparation = SharedAsyncPreparation<StreamingUnifiedAsrManager>()
    private let progress = VoiceModelProgressRelay()
    private var generation = 0
    private var sessionOpen = false
    private var loggedFirstFeed = false
    private var preparationAttemptID: UUID?

    func prepareIfNeeded() async {
        do {
            _ = try await prepare()
        } catch {
            Diag.log("voice preview model not ready: \(error.localizedDescription)")
        }
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        // Claiming a retry resets stale progress before this observer is
        // registered. A subscriber joining an in-flight attempt still gets
        // that attempt's latest fraction replayed.
        let attemptID = await claimPreparationAttempt()
        let token = progress.subscribe(onProgress)
        defer { progress.unsubscribe(token) }
        _ = try await manager(attemptID: attemptID)
    }

    func begin(onPartial: @escaping @Sendable (String) -> Void) async -> Int? {
        guard let manager = try? await manager() else { return nil }
        return try? await open(manager: manager, onPartial: onPartial)
    }

    private func open(
        manager: StreamingUnifiedAsrManager,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        generation += 1
        let active = generation
        loggedFirstFeed = false
        try await manager.reset()
        try Task.checkCancellation()
        guard active == generation else { throw CancellationError() }
        let firstPartial = PreviewLogOnce()
        await manager.setPartialTranscriptCallback { text in
            if firstPartial.mark() {
                Diag.log("voice preview first partial, chars=\(text.count)")
            }
            onPartial(text)
        }
        try Task.checkCancellation()
        guard active == generation else { throw CancellationError() }
        sessionOpen = true
        Diag.log("voice stream started")
        return active
    }

    func feed(_ frames: [PreviewAudioFrame], generation: Int) async {
        guard generation == self.generation, !frames.isEmpty else { return }
        guard await preparation.isPrepared(), let manager = try? await manager() else { return }
        guard let buffer = Self.joinedBuffer(frames) else { return }
        if !loggedFirstFeed {
            loggedFirstFeed = true
            Diag.log("voice first feed, frames=\(buffer.frameLength) peak=\(Self.peak(buffer))")
        }
        do {
            try await manager.appendAudio(buffer)
            guard generation == self.generation, sessionOpen else { return }
            try await manager.processBufferedAudio()
        } catch {
            Diag.log("voice stream chunk failed: \(error.localizedDescription)")
        }
    }

    /// Drain leftover audio, flush the decoder, return the note text.
    func finish(leftover: [PreviewAudioFrame], generation: Int?) async throws -> String {
        var active = generation
        if active == nil, sessionOpen { active = self.generation }
        if active == nil || active != self.generation || !sessionOpen {
            let manager = try await manager()
            active = try await open(manager: manager, onPartial: { _ in })
        }
        guard let active else { throw CancellationError() }
        if !leftover.isEmpty {
            await feed(leftover, generation: active)
        }
        guard active == self.generation, sessionOpen else { throw CancellationError() }
        let manager = try await manager()
        let text = try await manager.finish()
        guard active == self.generation, sessionOpen else { throw CancellationError() }
        await manager.setPartialTranscriptCallback { _ in }
        guard active == self.generation, sessionOpen else { throw CancellationError() }
        try await manager.reset()
        guard active == self.generation, sessionOpen else { throw CancellationError() }
        sessionOpen = false
        Diag.log("voice transcription finished, chars=\(text.count)")
        return text
    }

    func abandon() async {
        generation += 1
        let abandoned = generation
        sessionOpen = false
        guard await preparation.isPrepared(), let manager = try? await manager() else { return }
        await manager.setPartialTranscriptCallback { _ in }
        guard abandoned == generation else { return }
        try? await manager.reset()
    }

    private static func peak(_ buffer: AVAudioPCMBuffer) -> String {
        guard let data = buffer.floatChannelData?[0] else { return "none" }
        let count = Int(buffer.frameLength)
        var maxAbs: Float = 0
        for i in 0..<count { maxAbs = max(maxAbs, abs(data[i])) }
        return String(format: "%.3f", maxAbs)
    }

    private static func joinedBuffer(_ frames: [PreviewAudioFrame]) -> AVAudioPCMBuffer? {
        let sampleRate = frames[0].sampleRate
        let count = frames.reduce(0) { $0 + $1.samples.count }
        guard count > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let destination = buffer.floatChannelData?[0]
        else { return nil }
        var offset = 0
        for frame in frames where frame.sampleRate == sampleRate {
            frame.samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                destination.advanced(by: offset).update(from: base, count: source.count)
            }
            offset += frame.samples.count
        }
        buffer.frameLength = AVAudioFrameCount(offset)
        return offset > 0 ? buffer : nil
    }

    /// Returns the ID of the preparation attempt this caller joins. Only the
    /// first caller creates the ID and clears progress for that attempt.
    private func claimPreparationAttempt() async -> UUID? {
        if let preparationAttemptID { return preparationAttemptID }
        let isPrepared = await preparation.isPrepared()
        guard !isPrepared else { return nil }
        if let preparationAttemptID { return preparationAttemptID }
        let id = UUID()
        preparationAttemptID = id
        progress.reset()
        return id
    }

    private func manager(attemptID claimedID: UUID? = nil) async throws -> StreamingUnifiedAsrManager {
        let attemptID: UUID?
        if let claimedID {
            attemptID = claimedID
        } else {
            attemptID = await claimPreparationAttempt()
        }
        let progress = progress
        do {
            let loaded = try await preparation.value {
                let manager = StreamingUnifiedAsrManager(config: LocalVoiceModelFiles.streaming)
                try await manager.loadModels(
                    progressHandler: { @Sendable in progress.report($0.fractionCompleted) }
                )
                try await Self.prime(manager)
                Diag.log("voice model loaded")
                return manager
            }
            if preparationAttemptID == attemptID { preparationAttemptID = nil }
            await MainActor.run {
                NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
            }
            return loaded
        } catch {
            if preparationAttemptID == attemptID { preparationAttemptID = nil }
            throw error
        }
    }

    private static func prime(_ manager: StreamingUnifiedAsrManager) async throws {
        let samples = LocalVoiceModelFiles.streaming.chunkSamples + LocalVoiceModelFiles.streaming.rightSamples
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples)
        if let channel = buffer.floatChannelData?[0] {
            channel.update(repeating: 0, count: samples)
        }
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
        try await manager.reset()
    }
}

/// Mono float frames copied off the tap so the streaming actor can resample them.
nonisolated struct PreviewAudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double

    init?(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return nil }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }
        sampleRate = buffer.format.sampleRate
        if let channels = buffer.floatChannelData {
            samples = Self.loudest(channels, frames: frames, channelCount: channelCount)
        } else if buffer.format.commonFormat == .pcmFormatFloat32,
                  let pointer = buffer.audioBufferList.pointee.mBuffers.mData
        {
            let floats = pointer.assumingMemoryBound(to: Float.self)
            samples = Self.loudestInterleaved(floats, frames: frames, channelCount: channelCount)
        } else if let channels = buffer.int16ChannelData {
            let scale = 1 / Float(Int16.max)
            var best = 0
            var bestEnergy: Float = -1
            for channel in 0..<channelCount {
                var energy: Float = 0
                let source = channels[channel]
                for index in 0..<frames {
                    let sample = Float(source[index])
                    energy += sample * sample
                }
                if energy > bestEnergy {
                    bestEnergy = energy
                    best = channel
                }
            }
            let source = channels[best]
            samples = (0..<frames).map { Float(source[$0]) * scale }
        } else {
            return nil
        }
    }

    private static func loudest(
        _ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frames: Int,
        channelCount: Int
    ) -> [Float] {
        var best = 0
        var bestEnergy: Float = -1
        for channel in 0..<channelCount {
            var energy: Float = 0
            let source = channels[channel]
            for index in 0..<frames { energy += source[index] * source[index] }
            if energy > bestEnergy {
                bestEnergy = energy
                best = channel
            }
        }
        return Array(UnsafeBufferPointer(start: channels[best], count: frames))
    }

    private static func loudestInterleaved(
        _ floats: UnsafePointer<Float>,
        frames: Int,
        channelCount: Int
    ) -> [Float] {
        guard channelCount > 1 else {
            return Array(UnsafeBufferPointer(start: floats, count: frames))
        }
        var best = 0
        var bestEnergy: Float = -1
        for channel in 0..<channelCount {
            var energy: Float = 0
            for index in 0..<frames {
                let sample = floats[index * channelCount + channel]
                energy += sample * sample
            }
            if energy > bestEnergy {
                bestEnergy = energy
                best = channel
            }
        }
        return (0..<frames).map { floats[$0 * channelCount + best] }
    }
}

final class PreviewLogOnce: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var logged = false

    nonisolated func mark() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !logged else { return false }
        logged = true
        return true
    }
}

final class PreviewAudioQueue: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var items: [PreviewAudioFrame] = []

    nonisolated func append(_ frame: PreviewAudioFrame) {
        lock.lock()
        items.append(frame)
        lock.unlock()
    }

    nonisolated func drain() -> [PreviewAudioFrame] {
        lock.lock()
        let batch = items
        items.removeAll(keepingCapacity: true)
        lock.unlock()
        return batch
    }
}
