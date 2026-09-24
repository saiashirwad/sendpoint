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
    private var activeFormat: AVAudioFormat?
    private var spareEngine: AVAudioEngine?
    private var spareDevice: AudioInputDevice?
    private var spareFormat: AVAudioFormat?

    func prepare(_ order: MicrophoneOrder) {
        guard engine == nil, spareEngine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let device = AudioInputDeviceQuery.preferred(order),
              AudioInputDeviceQuery.bind(device, to: input) else { return }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        spareEngine = engine
        spareDevice = device
        spareFormat = format
        Diag.log("microphone prepared: \(device.name)")
    }

    func start(_ order: MicrophoneOrder, level: AsyncStream<Float>.Continuation,
               collectFrames: Bool) throws -> VoiceAudioQueue {
        stop()
        let engine = spareEngine ?? AVAudioEngine()
        let input = engine.inputNode
        guard let device = AudioInputDeviceQuery.preferred(order) else { throw MicrophoneError.noInputDevice }
        let cachedFormat = spareDevice?.id == device.id && spareDevice?.uid == device.uid
            ? spareFormat : nil
        if cachedFormat == nil && !AudioInputDeviceQuery.bind(device, to: input) {
            throw MicrophoneError.noInputDevice
        }
        let format = cachedFormat ?? input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneError.noInputDevice }
        spareEngine = nil
        spareDevice = nil
        spareFormat = nil

        let queue = VoiceAudioQueue()
        let label = collectFrames ? "voice" : "input preview"
        Diag.log("\(label) tap format: \(format.sampleRate)Hz ch=\(format.channelCount) interleaved=\(format.isInterleaved)")
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { @Sendable buffer, _ in
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
        activeFormat = format
        activeLabel = label
        Diag.log("\(label) recording started")
        return queue
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        spareEngine = engine
        spareDevice = activeDevice
        spareFormat = activeFormat
        activeDevice = nil
        activeFormat = nil
        Diag.log("\(activeLabel) recording stopped")
    }

    func teardown() {
        stop()
        spareEngine = nil
        spareDevice = nil
        spareFormat = nil
    }
}
