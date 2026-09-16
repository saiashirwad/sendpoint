import AppKit
import SwiftUI

enum VoiceCaptureLayout {
    static let pillHeight: CGFloat = 32
    static let shadowPadding: CGFloat = 24
    static let previewWidth: CGFloat = 420
    static let previewLines = 4
    static let previewLineHeight: CGFloat = 17
    static let previewLineSpacing: CGFloat = 2
    static let previewPaddingY: CGFloat = 10
    static var previewTextHeight: CGFloat {
        CGFloat(previewLines) * previewLineHeight + CGFloat(previewLines - 1) * previewLineSpacing
    }
    static var previewHeight: CGFloat {
        previewTextHeight + previewPaddingY * 2
    }
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

/// Live captions in their own panel, so the pill's layout never owns this card.
struct VoicePreviewCard: View {
    @Bindable var model: CaptureController
    @Environment(\.colorScheme) private var systemScheme

    private var palette: OverlayPalette { .against(systemScheme) }
    private var isVoice: Bool { model.state.session?.mode == .voice }

    var body: some View {
        Group {
            if isVoice {
                card
            }
        }
        .scaleEffect(isVoice ? 1 : 0.92)
        .opacity(isVoice ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isVoice)
        .animation(.easeOut(duration: 0.22), value: layout.rows.map(\.id))
        .environment(\.colorScheme, palette.contentScheme)
        .padding(VoiceCaptureLayout.shadowPadding)
        .frame(
            width: VoiceCaptureLayout.previewWidth + VoiceCaptureLayout.shadowPadding * 2,
            height: VoiceCaptureLayout.previewHeight + VoiceCaptureLayout.shadowPadding * 2,
            alignment: .bottom
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var card: some View {
        Group {
            if layout.rows.isEmpty {
                VoicePreviewWaiting(ink: palette.ink)
            } else {
                VoicePreviewLines(rows: layout.rows, overflow: layout.overflow, ink: palette.ink)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: VoiceCaptureLayout.previewTextHeight,
            maxHeight: VoiceCaptureLayout.previewTextHeight,
            alignment: .topLeading
        )
        .padding(.horizontal, 14)
        .padding(.vertical, VoiceCaptureLayout.previewPaddingY)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.paper))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                LinearGradient(
                    colors: [palette.ink.opacity(0.14), palette.ink.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var layout: (rows: [VoicePreviewLine], overflow: Bool) {
        let all = LiveTranscriptPreview.lines(
            for: model.state.session?.liveTranscript ?? "",
            width: VoiceCaptureLayout.previewWidth - 36,
            font: .ui(LiveTranscriptPreview.fontSize)
        )
        let start = max(0, all.count - VoiceCaptureLayout.previewLines)
        let rows = (start..<all.count).map { VoicePreviewLine(id: $0, text: all[$0]) }
        return (rows, all.count > VoiceCaptureLayout.previewLines)
    }

    private var accessibilityLabel: String {
        if !layout.rows.isEmpty {
            return "Live transcript: \(layout.rows.map(\.text).joined(separator: " "))"
        }
        return isVoice ? "Listening" : ""
    }
}

private struct VoicePreviewLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

/// Owns a snapshot of lines so a disappearing card cannot subscript a live array.
private struct VoicePreviewLines: View {
    let rows: [VoicePreviewLine]
    let overflow: Bool
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: VoiceCaptureLayout.previewLineSpacing) {
            ForEach(rows) { row in
                VoicePreviewLineText(text: row.text, ink: ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .mask {
            LinearGradient(
                stops: overflow
                    ? [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.28),
                        .init(color: .black, location: 1),
                    ]
                    : [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 1),
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct VoicePreviewWaiting: View {
    let ink: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(ink.opacity(0.22 + 0.5 * (0.5 + 0.5 * sin(time * 4.2 + Double(index) * 0.85))))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

private struct VoicePreviewLineText: View {
    let text: String
    let ink: Color

    var body: some View {
        Text(text)
            .font(.ui(LiveTranscriptPreview.fontSize))
            .foregroundStyle(ink.opacity(0.92))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: VoiceCaptureLayout.previewLineHeight, alignment: .center)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
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

/// Greedy word-wrap for the live card. Appending text only changes the last
/// line until it overflows, so completed lines stay put and shift up as a block.
enum LiveTranscriptPreview {
    static let fontSize: CGFloat = 12.5
    static let maxVisibleLines = 4

    static func lines(
        for text: String,
        width: CGFloat,
        font: NSFont
    ) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, width > 0 else { return [] }
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || measure(candidate, font: font) <= width {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func visible(_ lines: [String], max: Int = maxVisibleLines) -> [String] {
        Array(lines.suffix(max))
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
