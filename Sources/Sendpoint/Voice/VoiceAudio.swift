import AVFoundation
import Foundation

nonisolated struct VoiceAudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    init?(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return nil }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }
        sampleRate = buffer.format.sampleRate
        let stride = buffer.stride
        let interleaved = buffer.format.isInterleaved
        if let channels = buffer.floatChannelData {
            samples = Self.loudest(frames: frames, channelCount: channelCount) { frame, channel in
                channels[interleaved ? 0 : channel][frame * stride + (interleaved ? channel : 0)]
            }
        } else if let channels = buffer.int16ChannelData {
            let scale = 1 / Float(Int16.max)
            samples = Self.loudest(frames: frames, channelCount: channelCount) { frame, channel in
                Float(channels[interleaved ? 0 : channel][frame * stride + (interleaved ? channel : 0)]) * scale
            }
        } else {
            return nil
        }
    }

    private static func loudest(
        frames: Int,
        channelCount: Int,
        sample: (Int, Int) -> Float
    ) -> [Float] {
        var best = 0
        var bestEnergy: Float = -1
        for channel in 0..<channelCount {
            var energy: Float = 0
            for index in 0..<frames {
                let value = sample(index, channel)
                energy += value * value
            }
            if energy > bestEnergy {
                bestEnergy = energy
                best = channel
            }
        }
        return (0..<frames).map { sample($0, best) }
    }
}

nonisolated final class VoiceAudioTake: Sendable {
    let id: UUID
    let frames: AsyncStream<VoiceAudioFrame>
    private let continuation: AsyncStream<VoiceAudioFrame>.Continuation

    init(id: UUID = UUID()) {
        self.id = id
        (frames, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    @discardableResult
    func append(_ frame: VoiceAudioFrame) -> AsyncStream<VoiceAudioFrame>.Continuation.YieldResult {
        continuation.yield(frame)
    }

    func close() { continuation.finish() }
}
