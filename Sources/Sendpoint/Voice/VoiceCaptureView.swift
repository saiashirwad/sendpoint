import AppKit
import SwiftUI

enum VoiceCaptureLayout {
    static let pillHeight: CGFloat = 32
    static let shadowPadding: CGFloat = 24
    static let panelWidth: CGFloat = 680

    static let cardWidth: CGFloat = 420
    static let cardPaddingX: CGFloat = 14
    static let cardPaddingTop: CGFloat = 10
    static let cardPaddingBottom: CGFloat = 8
    static let cardFooterHeight: CGFloat = 24
    static let cardFooterGap: CGFloat = 6
    static let transcriptLineSpacing: CGFloat = 2

    static var transcriptWidth: CGFloat { cardWidth - cardPaddingX * 2 }

    static func transcriptLineHeight(fontSize: CGFloat) -> CGFloat {
        fontSize + 4.5
    }

    static func transcriptHeight(lines: Int, fontSize: CGFloat) -> CGFloat {
        let lines = VoiceSettings.clampedPreviewLines(lines)
        let lineHeight = transcriptLineHeight(fontSize: fontSize)
        return CGFloat(lines) * lineHeight + CGFloat(max(lines - 1, 0)) * transcriptLineSpacing
    }

    static func cardHeight(lines: Int, fontSize: CGFloat) -> CGFloat {
        cardPaddingTop + transcriptHeight(lines: lines, fontSize: fontSize)
            + cardFooterGap + cardFooterHeight + cardPaddingBottom
    }

    static func cardAnchorHeight(lines: Int, fontSize: CGFloat) -> CGFloat {
        cardHeight(lines: lines, fontSize: fontSize) - cardPaddingBottom
    }

    static func panelSize(card: Bool, lines: Int, fontSize: CGFloat) -> NSSize {
        let body = card ? cardHeight(lines: lines, fontSize: fontSize) : pillHeight
        return NSSize(width: panelWidth, height: body + shadowPadding * 2)
    }
}

struct VoiceCaptureView: View {
    @Bindable var model: CaptureController
    let meter: VoiceLevelMeter

    @Environment(\.colorScheme) private var systemScheme
    @State private var windowIsVisible = false

    private var appeared: Bool {
        guard let mode = model.state.session?.mode else { return false }
        return mode != .text
    }
    private var animates: Bool { windowIsVisible && appeared }

    private var palette: OverlayPalette { .against(systemScheme) }
    private var showsCard: Bool { model.transcriptionPreview }
    private var lineCount: Int { model.transcriptionPreviewLines }
    private var fontSize: CGFloat { CGFloat(model.transcriptionPreviewFontSize) }
    private var paperOpacity: Double { Double(model.transcriptionPreviewOpacity) / 100 }

    var body: some View {
        Group {
            if showsCard {
                card
            } else {
                pill
            }
        }
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: appeared)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tether)
        .animation(.easeOut(duration: 0.18), value: failureMessage)
        .environment(\.colorScheme, palette.contentScheme)
        .padding(VoiceCaptureLayout.shadowPadding)
        .frame(maxWidth: .infinity)
        .background(WindowVisibilityReporter(isVisible: $windowIsVisible))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice capture")
    }

    // MARK: - Capsule

    private var pill: some View {
        HStack(spacing: 10) {
            leading(rowHeight: VoiceCaptureLayout.pillHeight, anchorHeight: VoiceCaptureLayout.pillHeight)
            if let tether {
                divider
                tetherText(tether)
            }
            orb
                .padding(.leading, 2)
            failure
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .font(.uiBody)
        .frame(height: VoiceCaptureLayout.pillHeight)
        .background(Capsule().fill(palette.paper))
        .overlay(Capsule().strokeBorder(rim, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    // MARK: - Card

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: VoiceCaptureLayout.cardFooterGap) {
            transcriptBody
                .frame(
                    maxWidth: .infinity,
                    minHeight: VoiceCaptureLayout.transcriptHeight(lines: lineCount, fontSize: fontSize),
                    maxHeight: VoiceCaptureLayout.transcriptHeight(lines: lineCount, fontSize: fontSize),
                    alignment: .topLeading
                )
            HStack(spacing: 10) {
                leading(
                    rowHeight: VoiceCaptureLayout.cardFooterHeight,
                    anchorHeight: VoiceCaptureLayout.cardAnchorHeight(lines: lineCount, fontSize: fontSize)
                )
                if let tether {
                    divider
                    tetherText(tether)
                }
                Spacer(minLength: 8)
                failure
                orb
            }
            .font(.uiBody)
            .frame(height: VoiceCaptureLayout.cardFooterHeight)
        }
        .padding(.horizontal, VoiceCaptureLayout.cardPaddingX)
        .padding(.top, VoiceCaptureLayout.cardPaddingTop)
        .padding(.bottom, VoiceCaptureLayout.cardPaddingBottom)
        .frame(width: VoiceCaptureLayout.cardWidth)
        .background(shape.fill(palette.paper.opacity(paperOpacity)))
        .overlay(shape.strokeBorder(rim, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45 * paperOpacity), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.22), value: transcript.rows.map(\.id))
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if transcript.rows.isEmpty {
            VoiceTranscriptWaiting(ink: palette.ink, animates: animates && (orbMode == .idle || orbMode == .live))
        } else {
            VoiceTranscriptLines(
                rows: transcript.rows,
                overflow: transcript.overflow,
                ink: palette.ink,
                fontSize: fontSize
            )
        }
    }

    private var transcript: (rows: [VoiceTranscriptRow], overflow: Bool) {
        LiveTranscriptPreview.window(
            LiveTranscriptPreview.lines(
                for: model.state.session?.liveTranscript ?? "",
                width: VoiceCaptureLayout.transcriptWidth,
                font: .ui(fontSize)
            ),
            max: lineCount
        )
    }

    // MARK: - Shared controls

    @ViewBuilder
    private func leading(rowHeight: CGFloat, anchorHeight: CGFloat) -> some View {
        if let target = model.state.session?.dictationTarget {
            Text(target.appName ?? "Front app")
                .font(.ui(11.5, weight: .medium))
                .foregroundStyle(palette.ink.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            destination(rowHeight: rowHeight, anchorHeight: anchorHeight)
            noteCount
        }
    }

    private func destination(rowHeight: CGFloat, anchorHeight: CGFloat) -> some View {
        CaptureDestinationButton(
            model: model, mode: .voice, fontSize: 11.5,
            rowHeight: rowHeight, anchorHeight: anchorHeight
        )
        .foregroundStyle(palette.ink.opacity(0.9))
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var noteCount: some View {
        if let stack = model.targetStack {
            Text("\(stack.noteCount)")
                .font(.mono(11))
                .foregroundStyle(palette.ink.opacity(0.5))
                .padding(.leading, -4)
        }
    }

    private func tetherText(_ tether: String) -> some View {
        Text(tether)
            .font(.mono(11))
            .foregroundStyle(palette.ink.opacity(0.55))
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity.combined(with: .offset(x: 6)))
    }

    private var orb: some View {
        MeteredOrb(mode: orbMode, meter: meter, ink: palette.ink, amber: palette.amber, accent: palette.accent, animates: animates)
            .frame(width: 22, height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var failure: some View {
        if let failureMessage {
            Text(failureMessage)
                .font(.ui(11.5, weight: .medium))
                .foregroundStyle(palette.amber)
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.ink.opacity(0.12))
            .frame(width: 1, height: 12)
            .transition(.opacity)
    }

    private var rim: LinearGradient {
        LinearGradient(
            colors: [palette.ink.opacity(0.14), palette.ink.opacity(0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Copy

    private var orbMode: VoiceOrb.Mode {
        switch model.state.session?.phase {
        case .recording, .selectingVoice(recording: true, finishRequested: _): .live
        case .transcribing, .saving, .inserting: .thinking
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
        let destination: String
        if let target = model.state.session?.dictationTarget {
            destination = " Pasting into \(target.appName ?? "the front app")."
        } else {
            destination = model.targetStack.map { " Saving to \($0.name), \($0.countLabel)." } ?? ""
        }
        let transcript = showsCard && !self.transcript.rows.isEmpty
            ? " Live transcript: \(self.transcript.rows.map(\.text).joined(separator: " "))"
            : ""
        switch model.state.session?.phase {
        case .selectingVoice, .startingVoice, .recording: return "Voice body: listening.\(destination)\(transcript)"
        case .transcribing: return "Voice body: transcribing.\(destination)\(transcript)"
        case let .failed(message): return "Voice body: \(message)"
        case .saving: return "Voice body: saving.\(destination)"
        case .inserting: return "Voice body: pasting.\(destination)"
        default: return ""
        }
    }
}

struct VoiceTranscriptRow: Identifiable, Equatable {
    let id: Int
    let text: String
}

private struct VoiceTranscriptLines: View {
    let rows: [VoiceTranscriptRow]
    let overflow: Bool
    let ink: Color
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: VoiceCaptureLayout.transcriptLineSpacing) {
            ForEach(rows) { row in
                VoiceTranscriptLineText(text: row.text, ink: ink, fontSize: fontSize)
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

private struct VoiceTranscriptWaiting: View {
    let ink: Color
    let animates: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animates, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    dots(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                dots(at: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func dots(at time: TimeInterval) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(ink.opacity(0.22 + 0.5 * (0.5 + 0.5 * sin(time * 4.2 + Double(index) * 0.85))))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct VoiceTranscriptLineText: View {
    let text: String
    let ink: Color
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.ui(fontSize))
            .foregroundStyle(ink.opacity(0.92))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: VoiceCaptureLayout.transcriptLineHeight(fontSize: fontSize), alignment: .center)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
    }
}

private struct MeteredOrb: View {
    let mode: VoiceOrb.Mode
    let meter: VoiceLevelMeter
    let ink: Color
    let amber: Color
    let accent: Color
    let animates: Bool

    var body: some View {
        VoiceOrb(mode: mode, level: animates && mode == .live ? Double(meter.current) : 0,
                 ink: ink, amber: amber, accent: accent, animates: animates)
    }
}

enum VoiceOverlayCopy {
    static func tether(for text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        return words == 1 ? "1 word selected" : "\(words) words selected"
    }
}

enum LiveTranscriptPreview {
    static let fontSize: CGFloat = CGFloat(VoiceSettings.defaultPreviewFontSize)
    static let maxVisibleLines = VoiceSettings.defaultPreviewLines

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
        window(lines, max: max).rows.map(\.text)
    }

    static func window(_ lines: [String], max: Int) -> (rows: [VoiceTranscriptRow], overflow: Bool) {
        let start = Swift.max(0, lines.count - max)
        let rows = (start..<lines.count).map { VoiceTranscriptRow(id: $0, text: lines[$0]) }
        return (rows, lines.count > max)
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
