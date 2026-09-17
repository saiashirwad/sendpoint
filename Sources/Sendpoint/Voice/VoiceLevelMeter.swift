import AVFoundation
import Foundation
import Observation

/// Live microphone loudness, fed by the recording tap and read by the voice
/// overlay to size its orb. Rises at once and falls gently.
@Observable
final class VoiceLevelMeter {
    private(set) var current: Float = 0

    func push(_ level: Float) {
        current = max(level, current * 0.7)
    }

    func reset() {
        current = 0
    }

    /// Loudness in 0…1, on a decibel scale that puts quiet speech near 0.3
    /// and normal speech near 0.8.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let channel = channels[0]
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        let normalized = (decibels + 54) / 36
        return min(max(normalized, 0), 1)
    }
}
