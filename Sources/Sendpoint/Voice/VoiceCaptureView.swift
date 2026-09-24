import AppKit
import SendpointDomain
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

    static func cardSize(lines: Int, fontSize: CGFloat) -> NSSize {
        NSSize(width: cardWidth, height: cardHeight(lines: lines, fontSize: fontSize))
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

    @State private var windowIsVisible = false

    private var appeared: Bool {
        guard let mode = model.state.session?.mode else { return false }
        return mode != .text
    }
    private var animates: Bool { windowIsVisible && appeared }

    private let palette = OverlayPalette.dark
    private var showsCard: Bool { model.transcriptionPreview }
    private var lineCount: Int { model.transcriptionPreviewLines }
    private var fontSize: CGFloat { CGFloat(model.transcriptionPreviewFontSize) }
    private var paperOpacity: Double { Double(model.transcriptionPreviewOpacity) / 100 }

    var body: some View {
        Group {
            if showsCard {
                card(transcript)
            } else {
                pill
            }
        }
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: appeared)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: facts.tether)
        .animation(.easeOut(duration: 0.18), value: facts.failureText)
        .environment(\.colorScheme, .dark)
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
            CaptureTether(text: facts.tether, ink: palette.ink)
            orb(transcript: [])
                .padding(.leading, 2)
            failure
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .font(.uiBody)
        .frame(height: VoiceCaptureLayout.pillHeight)
        .background(Capsule().fill(palette.paper))
        .overlay(Capsule().strokeBorder(palette.rim, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    // MARK: - Card

    private typealias Transcript = (rows: [VoiceTranscriptRow], overflow: Bool)

    private func card(_ transcript: Transcript) -> some View {
        let shape = RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: VoiceCaptureLayout.cardFooterGap) {
            transcriptBody(transcript)
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
                CaptureTether(text: facts.tether, ink: palette.ink)
                Spacer(minLength: 8)
                failure
                orb(transcript: transcript.rows)
            }
            .font(.uiBody)
            .frame(height: VoiceCaptureLayout.cardFooterHeight)
        }
        .padding(.horizontal, VoiceCaptureLayout.cardPaddingX)
        .padding(.top, VoiceCaptureLayout.cardPaddingTop)
        .padding(.bottom, VoiceCaptureLayout.cardPaddingBottom)
        .frame(width: VoiceCaptureLayout.cardWidth)
        .background(shape.fill(palette.paper.opacity(paperOpacity)))
        .overlay(shape.strokeBorder(palette.rim, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45 * paperOpacity), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.22), value: transcript.rows.map(\.id))
    }

    @ViewBuilder
    private func transcriptBody(_ transcript: Transcript) -> some View {
        if transcript.rows.isEmpty {
            VoiceTranscriptWaiting(ink: palette.ink, animates: animates && (facts.orbMode == .idle || facts.orbMode == .live))
        } else {
            VoiceTranscriptLines(
                rows: transcript.rows,
                overflow: transcript.overflow,
                ink: palette.ink,
                fontSize: fontSize
            )
        }
    }

    private var transcript: Transcript {
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
            CaptureStackLabel(
                model: model, mode: .voice, ink: palette.ink,
                rowHeight: rowHeight, anchorHeight: anchorHeight
            )
        }
    }

    private func orb(transcript: [VoiceTranscriptRow]) -> some View {
        MeteredOrb(mode: facts.orbMode, meter: meter, ink: palette.ink, amber: palette.amber, accent: palette.accent, animates: animates)
            .frame(width: 22, height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(facts.accessibilityLabel(transcript: transcript.map(\.text)))
    }

    @ViewBuilder
    private var failure: some View {
        if let failureText = facts.failureText {
            Text(failureText)
                .font(.ui(11.5, weight: .medium))
                .foregroundStyle(palette.amber)
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(.opacity.combined(with: .offset(x: -6)))
        }
    }

    private var facts: VoiceOverlayFacts {
        VoiceOverlayFacts(
            phase: model.state.session?.phase,
            capturedText: model.captured?.text,
            dictationTarget: model.state.session?.dictationTarget,
            stackName: model.targetStack?.name,
            stackCount: model.targetStack?.countLabel
        )
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

nonisolated struct VoiceOverlayFacts: Equatable {
    let orbMode: VoiceOrb.Mode
    let failureText: String?
    let tether: String?

    private let phase: CapturePhase?
    private let dictationTarget: DictationTarget?
    private let stackName: String?
    private let stackCount: String?

    init(
        phase: CapturePhase?,
        capturedText: String?,
        dictationTarget: DictationTarget?,
        stackName: String?,
        stackCount: String?
    ) {
        self.phase = phase
        self.dictationTarget = dictationTarget
        self.stackName = stackName
        self.stackCount = stackCount
        switch phase {
        case .recording, .selectingVoice(recording: true, finishRequested: _):
            orbMode = .live
        case .transcribing, .saving, .inserting:
            orbMode = .thinking
        case .failed, .saveFailed:
            orbMode = .flat
        default:
            orbMode = .idle
        }
        if case let .failed(message) = phase {
            failureText = message
        } else {
            failureText = nil
        }
        tether = capturedText.flatMap(VoiceOverlayCopy.tether(for:))
    }

    func accessibilityLabel(transcript lines: [String]) -> String {
        let destination: String
        if let dictationTarget {
            destination = " Pasting into \(dictationTarget.appName ?? "the front app")."
        } else if let stackName, let stackCount {
            destination = " Saving to \(stackName), \(stackCount)."
        } else {
            destination = ""
        }
        let transcript = lines.isEmpty ? "" : " Live transcript: \(lines.joined(separator: " "))"
        switch phase {
        case .selectingVoice, .startingVoice, .recording: return "Voice body: listening.\(destination)\(transcript)"
        case .transcribing: return "Voice body: transcribing.\(destination)\(transcript)"
        case let .failed(message): return "Voice body: \(message)"
        case .saving: return "Voice body: saving.\(destination)"
        case .inserting: return "Voice body: pasting.\(destination)"
        default: return ""
        }
    }
}

nonisolated enum VoiceOverlayCopy {
    static func tether(for text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return nil }
        return words == 1 ? "1 word selected" : "\(words) words selected"
    }
}

enum LiveTranscriptPreview {
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

    static func window(_ lines: [String], max: Int) -> (rows: [VoiceTranscriptRow], overflow: Bool) {
        let start = Swift.max(0, lines.count - max)
        let rows = (start..<lines.count).map { VoiceTranscriptRow(id: $0, text: lines[$0]) }
        return (rows, lines.count > max)
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
