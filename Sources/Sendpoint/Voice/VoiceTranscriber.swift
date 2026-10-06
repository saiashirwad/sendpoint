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
    func transcribe(_ take: VoiceAudioTake, onPartial: @escaping @Sendable (String) -> Void) async throws -> String
    func teardown() async
}

nonisolated enum VoiceTranscriptionError: Error {
    case busy
}

nonisolated final class VoiceModelProgressRelay: @unchecked Sendable {
    private struct State {
        var observers: [Int: @Sendable (Double) -> Void] = [:]
        var nextID = 0
        var latest: Double?
    }

    private let state = Locked(State())

    @discardableResult
    func subscribe(_ observer: @escaping @Sendable (Double) -> Void) -> Int {
        let (id, replay) = state.withLock { state in
            state.nextID += 1
            let id = state.nextID
            state.observers[id] = observer
            return (id, state.latest)
        }
        if let replay { observer(replay) }
        return id
    }

    func unsubscribe(_ id: Int) {
        state.withLock { $0.observers[id] = nil }
    }

    func report(_ fraction: Double) {
        let current = state.withLock { state in
            state.latest = fraction
            return Array(state.observers.values)
        }
        for observer in current { observer(fraction) }
    }

    func reset() {
        state.withLock { $0.latest = nil }
    }
}

nonisolated struct VoiceStreamingEngine: Sendable {
    var reset: @Sendable () async throws -> Void
    var setPartial: @Sendable (@escaping @Sendable (String) -> Void) async -> Void
    var append: @Sendable (VoiceAudioFrame) async throws -> Void
    var finish: @Sendable () async throws -> String

    static func live(_ manager: StreamingUnifiedAsrManager) -> Self {
        Self(
            reset: { try await manager.reset() },
            setPartial: { await manager.setPartialTranscriptCallback($0) },
            append: { frame in
                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: frame.sampleRate, channels: 1, interleaved: false
                ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frame.samples.count)),
                   let destination = buffer.floatChannelData?[0]
                else { throw CocoaError(.fileReadCorruptFile) }
                frame.samples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { destination.update(from: base, count: source.count) }
                }
                buffer.frameLength = buffer.frameCapacity
                try Task.checkCancellation()
                try await manager.appendAudio(buffer)
                try Task.checkCancellation()
                try await manager.processBufferedAudio()
            },
            finish: { try await manager.finish() }
        )
    }
}

actor LocalStreamingTranscriber: VoiceTranscribing {
    private enum Preparation {
        case idle, loading(UUID, Task<VoiceStreamingEngine, Error>), ready(VoiceStreamingEngine), terminated
    }
    private var preparation = Preparation.idle
    private let progress = VoiceModelProgressRelay()
    private let load: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> VoiceStreamingEngine
    private var operation: (id: UUID, task: Task<String, Error>)?

    init(load: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> VoiceStreamingEngine = { progress in
        let manager = StreamingUnifiedAsrManager(config: LocalVoiceModelFiles.streaming)
        try await manager.loadModels(progressHandler: { progress($0.fractionCompleted) })
        try Task.checkCancellation()
        try await LocalStreamingTranscriber.prime(manager)
        try Task.checkCancellation()
        return .live(manager)
    }) {
        self.load = load
    }

    func prepareIfNeeded() async { try? await prepare() }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if case .idle = preparation { progress.reset() }
        let token = progress.subscribe(onProgress)
        defer { progress.unsubscribe(token) }
        _ = try await engine()
    }

    func transcribe(_ take: VoiceAudioTake, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        try Task.checkCancellation()
        if case .terminated = preparation { throw CancellationError() }
        guard operation == nil else { throw VoiceTranscriptionError.busy }
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            let engine = try await self.engine()
            try Task.checkCancellation()
            return try await Self.consume(take, engine: engine, onPartial: onPartial)
        }
        operation = (id, task)
        defer { if operation?.id == id { operation = nil } }
        return try await withTaskCancellationHandler {
            let text = try await task.value
            try Task.checkCancellation()
            return text
        } onCancel: { task.cancel() }
    }

    func teardown() async {
        if case .terminated = preparation { return }
        let loading: Task<VoiceStreamingEngine, Error>?
        if case let .loading(_, task) = preparation { loading = task } else { loading = nil }
        preparation = .terminated
        loading?.cancel()
        let running = operation?.task
        running?.cancel()
        _ = try? await running?.value
        _ = try? await loading?.value
        operation = nil
    }

    private nonisolated static func consume(
        _ take: VoiceAudioTake, engine: VoiceStreamingEngine, onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let outcome: Result<String, Error>
        do {
            try await engine.reset()
            try Task.checkCancellation()
            await engine.setPartial(onPartial)
            try Task.checkCancellation()
            for await frame in take.frames {
                try Task.checkCancellation()
                try await engine.append(frame)
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            let text = try await engine.finish()
            try Task.checkCancellation()
            outcome = .success(text)
        } catch { outcome = .failure(error) }
        await engine.setPartial { _ in }
        try await engine.reset()
        return try outcome.get()
    }

    private func engine() async throws -> VoiceStreamingEngine {
        try Task.checkCancellation()
        let id: UUID
        let task: Task<VoiceStreamingEngine, Error>
        switch preparation {
        case .terminated: throw CancellationError()
        case let .ready(engine): return engine
        case let .loading(activeID, activeTask): (id, task) = (activeID, activeTask)
        case .idle:
            id = UUID()
            progress.reset()
            task = Task { [load, progress] in
                try Task.checkCancellation()
                let engine = try await load { progress.report($0) }
                try Task.checkCancellation()
                return engine
            }
            preparation = .loading(id, task)
        }
        let loaded: VoiceStreamingEngine
        do { loaded = try await task.value }
        catch {
            if case let .loading(activeID, _) = preparation, activeID == id { preparation = .idle }
            throw error
        }
        if case .terminated = preparation { throw CancellationError() }
        if case let .loading(activeID, _) = preparation, activeID == id {
            preparation = .ready(loaded)
            await MainActor.run {
                NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
            }
        }
        try Task.checkCancellation()
        return loaded
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
