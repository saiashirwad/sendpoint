import AVFoundation
import FluidAudio
import Foundation
import SendpointDomain

extension Notification.Name {
    nonisolated static let voiceModelDidBecomeReady = Notification.Name("Sendpoint.voiceModelDidBecomeReady")
}

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

nonisolated protocol VoiceTranscribing: Sendable {
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func prepareIfNeeded() async
    func begin(onPartial: @escaping @Sendable (String) -> Void) async -> Int?
    func feed(_ frames: [PreviewAudioFrame], generation: Int) async
    func finish(leftover: [PreviewAudioFrame], generation: Int?) async throws -> String
    func abandon() async
    func teardown() async
}

@MainActor
final class VoiceNoteService {
    private enum Lifecycle { case active, terminated }
    private var lifecycle = Lifecycle.active
    private let transcriber: any VoiceTranscribing
    private let makeSpareEngine: () -> AVAudioEngine?
    private var teardownTask: Task<Void, Never>?
    let levelMeter = VoiceLevelMeter()
    private var engine: AVAudioEngine?
    private var spareEngine: AVAudioEngine?
    private var audioQueue: PreviewAudioQueue?
    private var streamTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var tapContinuation: AsyncStream<Float>.Continuation?
    private var abandonment: (id: UUID, task: Task<Void, Never>)?
    private var streamGeneration: Int?
    private var recordingStartedAt: Date?
    private(set) var recordingEpoch = 0

    var preferredInputDeviceUID: String?
    var onPartialTranscript: (@Sendable (String) -> Void)?

    init(
        transcriber: any VoiceTranscribing = LocalStreamingPreview(),
        makeSpareEngine: @escaping () -> AVAudioEngine? = {
            guard PermissionCheck.isMicrophoneAuthorized else { return nil }
            let engine = AVAudioEngine()
            _ = engine.inputNode
            return engine
        }
    ) {
        self.transcriber = transcriber
        self.makeSpareEngine = makeSpareEngine
    }

    func teardown() {
        guard lifecycle == .active else { return }
        lifecycle = .terminated
        let warmUp = warmUpTask
        warmUp?.cancel()
        warmUpTask = nil
        _ = try? stopMicrophone()
        invalidateTapDelivery()
        levelMeter.reset()
        spareEngine?.stop()
        spareEngine = nil
        let pump = streamTask
        pump?.cancel()
        streamTask = nil
        let previous = abandonment?.task
        previous?.cancel()
        abandonment = nil
        audioQueue = nil
        streamGeneration = nil
        recordingStartedAt = nil
        onPartialTranscript = nil
        let transcriber = transcriber
        teardownTask = Task {
            await transcriber.teardown()
            await warmUp?.value
            await pump?.value
            await previous?.value
        }
    }

    func waitForTeardown() async {
        await teardownTask?.value
    }

    var isRecording: Bool { engine?.isRunning == true }

    func downloadVoiceModel(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        guard lifecycle == .active else { throw CancellationError() }
        try Task.checkCancellation()
        try await transcriber.prepare(onProgress: onProgress)
        try Task.checkCancellation()
        guard lifecycle == .active else { throw CancellationError() }
    }

    func requestMicrophoneAccess() async -> Bool {
        guard lifecycle == .active, !Task.isCancelled else { return false }
        switch PermissionCheck.microphonePermissionState {
        case .granted:
            return true
        case .notDetermined:
            let allowed = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { @Sendable allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return allowed && lifecycle == .active && !Task.isCancelled
        case .denied, .restricted:
            return false
        }
    }

    func warmUp() {
        guard lifecycle == .active else { return }
        if spareEngine == nil { spareEngine = makeSpareEngine() }
        guard warmUpTask == nil else { return }
        let transcriber = transcriber
        warmUpTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await transcriber.prepareIfNeeded()
            self?.warmUpTask = nil
        }
    }

    func startRecording() async throws {
        await finishPendingAbandonment()
        try Task.checkCancellation()
        guard lifecycle == .active else { throw CancellationError() }
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
        recordingEpoch += 1
        let epoch = recordingEpoch
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
        try Task.checkCancellation()
        guard lifecycle == .active else { throw CancellationError() }
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
        guard lifecycle == .active else { throw CancellationError() }
        return transcript.nonblank ?? ""
    }

    func discardRecording() {
        guard lifecycle == .active else { return }
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

    private func invalidateTapDelivery() {
        recordingEpoch += 1
        meterTask?.cancel()
        meterTask = nil
        tapContinuation?.finish()
        tapContinuation = nil
    }

    func applyTapLevel(_ level: Float, epoch: Int) {
        guard lifecycle == .active, epoch == recordingEpoch else { return }
        levelMeter.push(level)
    }

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

    private func applyStreamGeneration(_ generation: Int, for queue: PreviewAudioQueue) {
        guard audioQueue === queue else { return }
        streamGeneration = generation
    }

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

nonisolated final class VoiceModelProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [Int: @Sendable (Double) -> Void] = [:]
    private var nextID = 0
    private var latest: Double?

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

    func reset() {
        lock.lock()
        latest = nil
        lock.unlock()
    }
}

actor LocalStreamingPreview: VoiceTranscribing {
    private enum Preparation {
        case idle
        case loading(UUID, Task<StreamingUnifiedAsrManager, Error>)
        case ready(StreamingUnifiedAsrManager)
        case terminated
    }
    private var preparation = Preparation.idle

    private var preparedManager: StreamingUnifiedAsrManager? {
        guard case .ready(let manager) = preparation else { return nil }
        return manager
    }

    func teardown() async {
        let previous = preparation
        guard case .terminated = previous else {
            preparation = .terminated
            generation += 1
            sessionOpen = false
            preparationAttemptID = nil
            switch previous {
            case .loading(_, let task):
                task.cancel()
            case .ready(let manager):
                await manager.setPartialTranscriptCallback { _ in }
                try? await manager.reset()
            case .idle, .terminated:
                break
            }
            return
        }
    }
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
        let attemptID = claimPreparationAttempt()
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
        guard let manager = preparedManager else { return }
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
        guard let manager = preparedManager else { return }
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

    private func claimPreparationAttempt() -> UUID? {
        if case .terminated = preparation { return nil }
        if let preparationAttemptID { return preparationAttemptID }
        guard preparedManager == nil else { return nil }
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
            attemptID = claimPreparationAttempt()
        }
        let progress = progress
        do {
            try Task.checkCancellation()
            let id: UUID
            let task: Task<StreamingUnifiedAsrManager, Error>
            switch preparation {
            case .terminated:
                throw CancellationError()
            case .ready(let manager):
                return manager
            case .loading(let activeID, let activeTask):
                id = activeID
                task = activeTask
            case .idle:
                id = UUID()
                task = Task {
                    try Task.checkCancellation()
                    let manager = StreamingUnifiedAsrManager(config: LocalVoiceModelFiles.streaming)
                    try await manager.loadModels(
                        progressHandler: { @Sendable in progress.report($0.fractionCompleted) }
                    )
                    try Task.checkCancellation()
                    try await Self.prime(manager)
                    try Task.checkCancellation()
                    Diag.log("voice model loaded")
                    return manager
                }
                preparation = .loading(id, task)
            }
            let loaded: StreamingUnifiedAsrManager
            do {
                loaded = try await task.value
            } catch {
                if case .loading(let activeID, _) = preparation, activeID == id {
                    preparation = .idle
                }
                throw error
            }
            if case .terminated = preparation { throw CancellationError() }
            if case .loading(let activeID, _) = preparation, activeID == id {
                preparation = .ready(loaded)
            }
            try Task.checkCancellation()
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
