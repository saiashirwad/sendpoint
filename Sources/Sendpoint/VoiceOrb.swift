import SwiftUI

/// One small circle of sound. Live loudness swells it; while waiting it
/// breathes; while busy it pulses; when something failed it sits still and
/// amber.
struct VoiceOrb: View {
    enum Mode: Equatable {
        case idle
        case live
        case thinking
        case flat
    }

    let mode: Mode
    /// 0…1 loudness on the speech-centred scale of `VoiceLevelMeter`.
    let level: Double
    let ink: Color
    let amber: Color

    private let restingDiameter: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: mode == .flat || mode == .live)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                switch mode {
                case .live:
                    // A soft halo grows faster than the core so loud moments
                    // read as a bloom rather than a bigger dot.
                    Circle()
                        .fill(ink.opacity(0.18))
                        .frame(
                            width: restingDiameter + 14 * shaped(level),
                            height: restingDiameter + 14 * shaped(level)
                        )
                    Circle()
                        .fill(ink.opacity(0.95))
                        .frame(
                            width: restingDiameter + 5 * shaped(level),
                            height: restingDiameter + 5 * shaped(level)
                        )
                case .idle:
                    let breath = 0.5 + 0.5 * sin(time * 2.2)
                    Circle()
                        .fill(ink.opacity(0.3 + 0.25 * breath))
                        .frame(width: restingDiameter, height: restingDiameter)
                case .thinking:
                    let pulse = 0.5 + 0.5 * sin(time * 5)
                    Circle()
                        .strokeBorder(ink.opacity(0.35 + 0.4 * pulse), lineWidth: 1.4)
                        .frame(
                            width: restingDiameter + 2 + 3 * pulse,
                            height: restingDiameter + 2 + 3 * pulse
                        )
                case .flat:
                    Circle()
                        .fill(amber.opacity(0.9))
                        .frame(width: restingDiameter, height: restingDiameter)
                }
            }
            .animation(.linear(duration: 0.05), value: level)
        }
    }

    /// Quiet speech still moves the orb a little; loud speech does not pin it.
    private func shaped(_ level: Double) -> CGFloat {
        CGFloat(pow(min(max(level, 0), 1), 1.3))
    }
}
