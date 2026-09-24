import AVFoundation
import Foundation

struct Microphone {
    var requestAccess: () async -> Bool
    var prepare: (MicrophoneOrder) async -> Void
    var start: (MicrophoneOrder) async throws -> VoiceAudioQueue
    var stop: () async -> Void
    var teardown: () async -> Void = {}

    static func live(meter: VoiceLevelMeter, collectFrames: Bool = true) -> Microphone {
        let hardware = MicrophoneHardware()
        let levels = LatestValuePump<Float>()
        return Microphone(
            requestAccess: { await PermissionCheck.requestMicrophoneAccess() },
            prepare: { order in
                guard PermissionCheck.isMicrophoneAuthorized else { return }
                await hardware.prepare(order)
            },
            start: { order in
                let level = levels.start { meter.push($0) }
                do {
                    return try await hardware.start(order, level: level, collectFrames: collectFrames)
                } catch {
                    levels.stop()
                    meter.reset()
                    throw error
                }
            },
            stop: {
                levels.stop()
                meter.reset()
                await hardware.stop()
            },
            teardown: {
                levels.stop()
                meter.reset()
                await hardware.teardown()
            }
        )
    }
}

nonisolated private enum MicrophoneError: LocalizedError {
    case noInputDevice

    var errorDescription: String? { "No microphone is available. Check the list in Settings › Capture." }
}

private actor MicrophoneHardware {
    private var engine: AVAudioEngine?
    private var activeLabel = "voice"
    private var activeDevice: AudioInputDevice?
    private var spareEngine: AVAudioEngine?
    private var spareDevice: AudioInputDevice?

    func prepare(_ order: MicrophoneOrder) {
        guard engine == nil, spareEngine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let device = AudioInputDeviceQuery.preferred(order),
              AudioInputDeviceQuery.bind(device, to: input),
              Self.tapFormat(of: input) != nil
        else { return }
        spareEngine = engine
        spareDevice = device
        Diag.log("microphone prepared: \(device.name)")
    }

    func start(_ order: MicrophoneOrder, level: AsyncStream<Float>.Continuation,
               collectFrames: Bool) throws -> VoiceAudioQueue {
        stop()
        guard let device = AudioInputDeviceQuery.preferred(order) else { throw MicrophoneError.noInputDevice }
        let (engine, format) = try boundEngine(for: device)
        let input = engine.inputNode

        let queue = VoiceAudioQueue()
        let label = collectFrames ? "voice" : "input preview"
        Diag.log("\(label) tap format: \(format.sampleRate)Hz ch=\(format.channelCount) interleaved=\(format.isInterleaved)")
        try Self.installTap(on: input, format: format) { @Sendable buffer, _ in
            if collectFrames, let frame = VoiceAudioFrame(buffer: buffer) {
                queue.append(frame)
            }
            level.yield(VoiceLevelMeter.level(of: buffer))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        activeDevice = device
        activeLabel = label
        Diag.log("\(label) recording started")
        return queue
    }

    private func boundEngine(for device: AudioInputDevice) throws -> (AVAudioEngine, AVAudioFormat) {
        let spare = spareEngine
        let spareMatches = spareDevice?.id == device.id && spareDevice?.uid == device.uid
        spareEngine = nil
        spareDevice = nil
        if let spare, spareMatches {
            AudioInputDeviceQuery.matchRate(of: device, on: spare.inputNode)
            if let format = Self.tapFormat(of: spare.inputNode) { return (spare, format) }
            Diag.log("microphone format changed on \(device.name); binding a new engine")
        }
        let engine = (spareMatches ? nil : spare) ?? AVAudioEngine()
        guard AudioInputDeviceQuery.bind(device, to: engine.inputNode),
              let format = Self.tapFormat(of: engine.inputNode)
        else { throw MicrophoneError.noInputDevice }
        return (engine, format)
    }

    private static func tapFormat(of input: AVAudioInputNode) -> AVAudioFormat? {
        MicrophoneTapFormat.valid(output: input.outputFormat(forBus: 0), hardware: input.inputFormat(forBus: 0))
    }

    private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                   block: @escaping AVAudioNodeTapBlock) throws {
        if #available(macOS 27, *) {
            try input.__installTap(onBus: 0, bufferSize: 2_048, format: format, error: (), block: block)
        } else {
            input.installTap(onBus: 0, bufferSize: 2_048, format: format, block: block)
        }
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        spareEngine = engine
        spareDevice = activeDevice
        activeDevice = nil
        Diag.log("\(activeLabel) recording stopped")
    }

    func teardown() {
        stop()
        spareEngine = nil
        spareDevice = nil
    }
}

nonisolated enum MicrophoneTapFormat {
    static func valid(output: AVAudioFormat, hardware: AVAudioFormat) -> AVAudioFormat? {
        guard output.sampleRate > 0, output.channelCount > 0,
              output.sampleRate == hardware.sampleRate else { return nil }
        return output
    }
}
