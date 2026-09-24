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
    func begin(_ take: UUID, onPartial: @escaping @Sendable (String) -> Void) async -> Bool
    func feed(_ frames: [VoiceAudioFrame], take: UUID) async
    func finish(_ take: UUID, leftover: [VoiceAudioFrame]) async throws -> String
    func abandon() async
    func teardown() async
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

actor LocalStreamingTranscriber: VoiceTranscribing {
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
            session = nil
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
    private var session: (take: UUID, isOpen: Bool)?
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

    func begin(_ take: UUID, onPartial: @escaping @Sendable (String) -> Void) async -> Bool {
        guard let manager = try? await manager() else { return false }
        return (try? await open(take, manager: manager, onPartial: onPartial)) != nil
    }

    private func owns(_ take: UUID) -> Bool {
        session?.take == take && session?.isOpen == true
    }

    private func open(
        _ take: UUID,
        manager: StreamingUnifiedAsrManager,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws {
        session = (take, false)
        loggedFirstFeed = false
        try await manager.reset()
        try Task.checkCancellation()
        guard session?.take == take else { throw CancellationError() }
        let firstPartial = TranscriberLogOnce()
        await manager.setPartialTranscriptCallback { text in
            if firstPartial.mark() {
                Diag.log("voice preview first partial, chars=\(text.count)")
            }
            onPartial(text)
        }
        try Task.checkCancellation()
        guard session?.take == take else { throw CancellationError() }
        session = (take, true)
        Diag.log("voice stream started")
    }

    func feed(_ frames: [VoiceAudioFrame], take: UUID) async {
        guard owns(take), !frames.isEmpty else { return }
        guard let manager = preparedManager else { return }
        guard let buffer = Self.joinedBuffer(frames) else { return }
        if !loggedFirstFeed {
            loggedFirstFeed = true
            Diag.log("voice first feed, frames=\(buffer.frameLength) peak=\(Self.peak(buffer))")
        }
        do {
            try await manager.appendAudio(buffer)
            guard owns(take) else { return }
            try await manager.processBufferedAudio()
        } catch {
            Diag.log("voice stream chunk failed: \(error.localizedDescription)")
        }
    }

    func finish(_ take: UUID, leftover: [VoiceAudioFrame]) async throws -> String {
        if !owns(take) {
            try await open(take, manager: try await manager(), onPartial: { _ in })
        }
        await feed(leftover, take: take)
        guard owns(take) else { throw CancellationError() }
        let manager = try await manager()
        let text = try await manager.finish()
        guard owns(take) else { throw CancellationError() }
        await manager.setPartialTranscriptCallback { _ in }
        guard owns(take) else { throw CancellationError() }
        try await manager.reset()
        guard owns(take) else { throw CancellationError() }
        session = nil
        Diag.log("voice transcription finished, chars=\(text.count)")
        return text
    }

    func abandon() async {
        session = nil
        guard let manager = preparedManager else { return }
        await manager.setPartialTranscriptCallback { _ in }
        guard session == nil else { return }
        try? await manager.reset()
    }

    private static func peak(_ buffer: AVAudioPCMBuffer) -> String {
        guard let data = buffer.floatChannelData?[0] else { return "none" }
        let count = Int(buffer.frameLength)
        var maxAbs: Float = 0
        for i in 0..<count { maxAbs = max(maxAbs, abs(data[i])) }
        return String(format: "%.3f", maxAbs)
    }

    private static func joinedBuffer(_ frames: [VoiceAudioFrame]) -> AVAudioPCMBuffer? {
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

final class TranscriberLogOnce: @unchecked Sendable {
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
