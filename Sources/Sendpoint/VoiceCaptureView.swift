import SwiftUI

enum VoiceCaptureLayout {
    static let pillHeight: CGFloat = 32
    static let shadowPadding: CGFloat = 24
}

/// A compact recording capsule that stays visible below its destination picker.
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
            CaptureDestinationButton(model: model, mode: .voice, fontSize: 11.5)
                .foregroundStyle(palette.ink.opacity(0.9))
                .frame(maxWidth: 180, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if let stack = model.targetStack {
                Text("\(stack.noteCount)")
                    .font(.mono(11))
                    .foregroundStyle(palette.ink.opacity(0.5))
                    .padding(.leading, -4)
            }
            if let tether {
                divider
                Text(tether)
                    .font(.mono(11))
                    .foregroundStyle(palette.ink.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: 6)))
            }
            MeteredOrb(mode: orbMode, meter: meter, ink: palette.ink, amber: palette.amber, accent: palette.accent)
                .frame(width: 22, height: 22)
                .padding(.leading, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
            if let failureMessage {
                Text(failureMessage)
                    .font(.ui(11.5, weight: .medium))
                    .foregroundStyle(palette.amber)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .font(.uiBody)
        .frame(height: VoiceCaptureLayout.pillHeight)
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
        .padding(VoiceCaptureLayout.shadowPadding)
        // The hosting panel is wider than the capsule so the tether and a
        // failure message can appear later without the window resizing.
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice capture")
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
    private var orbMode: VoiceOrb.Mode {
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
    let mode: VoiceOrb.Mode
    let meter: VoiceLevelMeter
    let ink: Color
    let amber: Color
    let accent: Color

    var body: some View {
        VoiceOrb(mode: mode, level: Double(meter.current), ink: ink, amber: amber, accent: accent)
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


