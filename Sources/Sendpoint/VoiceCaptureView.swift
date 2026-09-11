import SwiftUI

/// The press-and-hold voice overlay: a low, wordless capsule. It says where
/// the note is going, the stack's name and how many notes are already there,
/// and its only moving part is a single orb of sound that swells with the
/// voice while listening, breathes while the transcript is made, and turns
/// amber only when something actually went wrong. When the note is tied to a
/// selection, a dim word count sits beside the orb, so it is clear the words
/// will attach to something without echoing it back. The capsule inverts
/// against the system appearance so it never sinks into a same-coloured
/// desktop.
struct VoiceCaptureView: View {
    @Bindable var model: CaptureController
    let meter: VoiceLevelMeter

    @Environment(\.colorScheme) private var systemScheme

    /// The overlay window is built once at launch and kept, so the entrance
    /// animation keys off the stack rather than the view's first appearance.
    private var appeared: Bool { model.state.session?.mode == .voice }

    private var palette: OverlayPalette { .against(systemScheme) }

    var body: some View {
        HStack(spacing: 10) {
            if let stack = model.targetStack {
                Text(stack.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.ink.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(stack.noteCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.45))
                    .padding(.leading, -4)
            }
            if let tether {
                divider
                Text(tether)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: 6)))
            }
            MeteredOrb(mode: orbMode, meter: meter, ink: palette.ink, amber: palette.amber)
                .frame(width: 22, height: 22)
                .padding(.leading, 2)
            if let failureMessage {
                Text(failureMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.amber)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(Capsule().fill(palette.paper))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [palette.ink.opacity(0.14), palette.ink.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: appeared)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tether)
        .animation(.easeOut(duration: 0.18), value: failureMessage)
        .environment(\.colorScheme, palette.contentScheme)
        .padding(24)
        // The hosting panel is wider than the capsule so the tether and a
        // failure message can appear later without the window resizing.
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.ink.opacity(0.12))
            .frame(width: 1, height: 12)
            .transition(.opacity)
    }

    // MARK: - Copy

    // Reading the selection happens while the microphone is already open, so
    // the overlay never mentions it: from the user's side it is all listening.
    private var orbMode: Orb.Mode {
        switch model.state.session?.phase {
        case .recording, .selectingVoice(recording: true, finishRequested: _): .live
        case .transcribing, .saving: .thinking
        case .failed, .saveFailed: .flat
        default: .idle
        }
    }

    private var tether: String? {
        guard let text = model.captured?.text else { return nil }
        return VoiceOverlayCopy.tether(for: text)
    }

    private var failureMessage: String? {
        if case let .failed(message) = model.state.session?.phase { return message }
        return nil
    }

    private var accessibilityLabel: String {
        let destination = model.targetStack.map { " Saving to \($0.name), \($0.countLabel)." } ?? ""
        switch model.state.session?.phase {
        case .selectingVoice, .startingVoice, .recording: return "Voice body: listening.\(destination)"
        case .transcribing: return "Voice body: transcribing.\(destination)"
        case let .failed(message): return "Voice body: \(message)"
        case .saving: return "Voice body: saving.\(destination)"
        default: return ""
        }
    }
}

/// The only view that reads the meter, so its tap-rate updates re-render the
/// orb alone rather than the whole overlay.
private struct MeteredOrb: View {
    let mode: Orb.Mode
    let meter: VoiceLevelMeter
    let ink: Color
    let amber: Color

    var body: some View {
        Orb(mode: mode, level: Double(meter.current), ink: ink, amber: amber)
    }
}

/// Pure text shaping for the overlay.
enum VoiceOverlayCopy {
    /// How much is selected, without repeating it. `nil` when nothing is.
    static func tether(for text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        return words == 1 ? "1 word" : "\(words) words"
    }
}

/// One small circle of sound. Live loudness swells it; while waiting it
/// breathes; while busy it pulses; when something failed it sits still and
/// amber.
private struct Orb: View {
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
                        .frame(width: restingDiameter + 14 * shaped(level), height: restingDiameter + 14 * shaped(level))
                    Circle()
                        .fill(ink.opacity(0.95))
                        .frame(width: restingDiameter + 5 * shaped(level), height: restingDiameter + 5 * shaped(level))
                case .idle:
                    let breath = 0.5 + 0.5 * sin(time * 2.2)
                    Circle()
                        .fill(ink.opacity(0.3 + 0.25 * breath))
                        .frame(width: restingDiameter, height: restingDiameter)
                case .thinking:
                    let pulse = 0.5 + 0.5 * sin(time * 5)
                    Circle()
                        .strokeBorder(ink.opacity(0.35 + 0.4 * pulse), lineWidth: 1.4)
                        .frame(width: restingDiameter + 2 + 3 * pulse, height: restingDiameter + 2 + 3 * pulse)
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
