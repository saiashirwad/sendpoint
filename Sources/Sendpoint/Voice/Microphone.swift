import AVFoundation
import Foundation

struct Microphone {
    var requestAccess: () async -> Bool
    var prepare: () -> Void
    var start: (_ deviceUID: String?) throws -> PreviewAudioQueue
    var stop: () -> Void

    static func live(meter: VoiceLevelMeter) -> Microphone {
        let microphone = LiveMicrophone(meter: meter)
        return Microphone(
            requestAccess: { await PermissionCheck.requestMicrophoneAccess() },
            prepare: { microphone.prepare() },
            start: { try microphone.start(deviceUID: $0) },
            stop: { microphone.stop() }
        )
    }
}

private enum MicrophoneError: LocalizedError {
    case noInputDevice

    var errorDescription: String? { "No microphone is available." }
}

private final class LiveMicrophone {
    private let meter: VoiceLevelMeter
    private let levels = LatestValuePump<Float>()
    private var engine: AVAudioEngine?
    private var spareEngine: AVAudioEngine?

    init(meter: VoiceLevelMeter) {
        self.meter = meter
    }

    func prepare() {
        guard spareEngine == nil, PermissionCheck.isMicrophoneAuthorized else { return }
        let engine = AVAudioEngine()
        _ = engine.inputNode
        spareEngine = engine
    }

    func start(deviceUID: String?) throws -> PreviewAudioQueue {
        stop()
        let engine = spareEngine ?? AVAudioEngine()
        spareEngine = nil
        let input = engine.inputNode
        selectInputDevice(uid: deviceUID, on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneError.noInputDevice }

        let queue = PreviewAudioQueue()
        let meter = meter
        let level = levels.start { meter.push($0) }
        Diag.log("voice tap format: \(format.sampleRate)Hz ch=\(format.channelCount) interleaved=\(format.isInterleaved)")
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { @Sendable buffer, _ in
            if let frame = PreviewAudioFrame(buffer: buffer) {
                queue.append(frame)
            }
            level.yield(VoiceLevelMeter.level(of: buffer))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            levels.stop()
            throw error
        }
        self.engine = engine
        Diag.log("voice recording started")
        return queue
    }

    func stop() {
        levels.stop()
        meter.reset()
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        Diag.log("voice recording stopped")
    }

    private func selectInputDevice(uid: String?, on input: AVAudioInputNode) {
        let device = InputDeviceChoice.resolve(
            preferredUID: uid,
            available: AudioInputDeviceQuery.allInputs()
        ) ?? AudioInputDeviceQuery.defaultInput()
        guard let device else { return }
        if AudioInputDeviceQuery.select(device, on: input) {
            Diag.log("voice input device: \(device.name)")
        }
    }
}
