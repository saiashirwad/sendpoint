import AVFoundation

nonisolated struct VoiceAudioFrame: Sendable {
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

nonisolated final class VoiceAudioQueue: @unchecked Sendable {
    private let items = Locked<[VoiceAudioFrame]>([])

    nonisolated func append(_ frame: VoiceAudioFrame) {
        items.withLock { $0.append(frame) }
    }

    nonisolated func drain() -> [VoiceAudioFrame] {
        items.withLock { items in
            let batch = items
            items.removeAll(keepingCapacity: true)
            return batch
        }
    }
}
