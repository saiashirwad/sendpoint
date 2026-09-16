import SwiftUI

/// Live loudness swells the orb; only visible, active work gets a pulse.
/// Idle and failed states are static, including the setup wordmark.
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
    /// What the orb turns while it listens: the one moment it wears the
    /// brand colour.
    let accent: Color
    var animates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let restingDiameter: CGFloat = 8

    var body: some View {
        if mode == .thinking, animates, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                orb(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            orb(at: 0)
        }
    }

    private func orb(at time: TimeInterval) -> some View {
        ZStack {
            switch mode {
            case .live:
                // A soft halo grows faster than the core so loud moments
                // read as a bloom rather than a bigger dot.
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(
                        width: restingDiameter + 14 * shaped(level),
                        height: restingDiameter + 14 * shaped(level)
                    )
                Circle()
                    .fill(accent)
                    .frame(
                        width: restingDiameter + 5 * shaped(level),
                        height: restingDiameter + 5 * shaped(level)
                    )
            case .idle:
                Circle()
                    .fill(ink.opacity(0.425))
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
        .animation(animates && !reduceMotion ? .linear(duration: 0.05) : nil, value: level)
    }

    /// Quiet speech still moves the orb a little; loud speech does not pin it.
    private func shaped(_ level: Double) -> CGFloat {
        CGFloat(pow(min(max(level, 0), 1), 1.3))
    }
}
