import SwiftUI

struct VoiceOrb: View {
    enum Mode: Equatable {
        case idle
        case live
        case thinking
        case flat
    }

    let mode: Mode
    let level: Double
    let ink: Color
    let amber: Color
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

    private func shaped(_ level: Double) -> CGFloat {
        CGFloat(pow(min(max(level, 0), 1), 1.3))
    }
}

// MARK: - Previews

#Preview("VoiceOrb modes") {
    HStack(spacing: 28) {
        VStack(spacing: 8) {
            VoiceOrb(mode: .idle, level: 0, ink: .primary, amber: .orange, accent: .pink)
            Text("idle").font(.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: 8) {
            VoiceOrb(mode: .live, level: 0.7, ink: .primary, amber: .orange, accent: .pink)
            Text("live").font(.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: 8) {
            VoiceOrb(mode: .thinking, level: 0, ink: .primary, amber: .orange, accent: .pink)
            Text("thinking").font(.caption).foregroundStyle(.secondary)
        }
        VStack(spacing: 8) {
            VoiceOrb(mode: .flat, level: 0, ink: .primary, amber: .orange, accent: .pink)
            Text("flat").font(.caption).foregroundStyle(.secondary)
        }
    }
    .padding()
}
