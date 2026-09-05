import SwiftUI

/// The press-and-hold voice overlay: a low, wordless capsule whose only
/// moving part is a single ribbon of sound. The ribbon's motion is the state
/// language: it swells with the voice while listening, settles into a hairline
/// with a passing light while the transcript is made, and turns amber only
/// when something actually went wrong. When the note is tied to a selection,
/// a dim snippet of that text sits beside the ribbon so it is clear what the
/// words will attach to.
struct VoiceCaptureView: View {
    @Bindable var model: CaptureController
    let meter: VoiceLevelMeter

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            if let tether {
                Text(tether)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: 6)))
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 12)
                    .transition(.opacity)
            }
            Ribbon(mode: ribbonMode, samples: meter.samples)
                .frame(width: 112, height: 22)
            if let failureMessage {
                Text(failureMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Ribbon.amber)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Capsule().fill(Color(white: 0.06).opacity(0.94)))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tether)
        .animation(.easeOut(duration: 0.18), value: failureMessage)
        .environment(\.colorScheme, .dark)
        .padding(24)
        // The hosting panel is wider than the capsule so the tether and a
        // failure message can appear later without the window resizing.
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Copy

    // Reading the selection happens while the microphone is already open, so
    // the overlay never mentions it: from the user's side it is all listening.
    private var ribbonMode: Ribbon.Mode {
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
        switch model.state.session?.phase {
        case .selectingVoice, .startingVoice, .recording: "Voice note: listening"
        case .transcribing: "Voice note: transcribing"
        case let .failed(message): "Voice note: \(message)"
        case .saving: "Voice note: saving"
        default: ""
        }
    }
}

/// Pure text shaping for the overlay.
enum VoiceOverlayCopy {
    static let tetherLimit = 28

    /// The first line of the selection, whitespace collapsed, cut to fit the
    /// capsule. `nil` when there is nothing worth showing.
    static func tether(for text: String) -> String? {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty }
        guard let firstLine else { return nil }
        if firstLine.count <= tetherLimit { return firstLine }
        return String(firstLine.prefix(tetherLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// One continuous line of sound. Live loudness scrolls through it as a
/// mirrored envelope; while waiting it is a breathing hairline; while busy a
/// light travels along it.
private struct Ribbon: View {
    enum Mode: Equatable {
        case idle
        case live
        case thinking
        case flat
    }

    static let amber = Color(red: 1.0, green: 0.72, blue: 0.38)

    let mode: Mode
    let samples: [Float]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: mode == .flat)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2
                switch mode {
                case .live:
                    let path = envelope(levels: smoothedLevels(), in: size)
                    canvas.fill(path, with: .color(Color.white.opacity(0.22)))
                    canvas.stroke(
                        path,
                        with: .color(Color.white.opacity(0.92)),
                        style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)
                    )
                case .idle:
                    let breath = 0.5 + 0.5 * sin(time * 2.2)
                    canvas.stroke(
                        hairline(in: size),
                        with: .color(Color.white.opacity(0.22 + 0.12 * breath)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                case .thinking:
                    canvas.stroke(
                        hairline(in: size),
                        with: .color(Color.white.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    let sweep = (time * 0.85).truncatingRemainder(dividingBy: 1)
                    let center = (-0.25 + 1.5 * sweep) * size.width
                    canvas.stroke(
                        hairline(in: size),
                        with: .linearGradient(
                            Gradient(colors: [.clear, Color.white.opacity(0.95), .clear]),
                            startPoint: CGPoint(x: center - 34, y: midY),
                            endPoint: CGPoint(x: center + 34, y: midY)
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                case .flat:
                    canvas.stroke(
                        hairline(in: size),
                        with: .color(Self.amber.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.12),
                    .init(color: .white, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func hairline(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        return path
    }

    /// Neighbour-averaged loudness, so the ribbon reads as one line rather
    /// than a row of spikes.
    private func smoothedLevels() -> [Double] {
        let raw = samples.map(Double.init)
        return raw.indices.map { index in
            let lower = max(0, index - 1)
            let upper = min(raw.count - 1, index + 1)
            let window = raw[lower...upper]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private func envelope(levels: [Double], in size: CGSize) -> Path {
        var path = Path()
        guard levels.count > 1 else { return path }
        let midY = size.height / 2
        let reach = size.height / 2 - 1
        let step = size.width / CGFloat(levels.count - 1)
        let amplitudes = levels.map { level -> CGFloat in
            let shaped = pow(max(0, level), 1.3)
            return reach * CGFloat(0.06 + 0.94 * shaped)
        }
        let top = amplitudes.enumerated().map { index, amplitude in
            CGPoint(x: CGFloat(index) * step, y: midY - amplitude)
        }
        let bottom = amplitudes.enumerated().reversed().map { index, amplitude in
            CGPoint(x: CGFloat(index) * step, y: midY + amplitude)
        }
        path.move(to: top[0])
        addSmoothCurve(through: top, to: &path)
        path.addLine(to: bottom[0])
        addSmoothCurve(through: bottom, to: &path)
        path.closeSubpath()
        return path
    }

    private func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
        guard points.count > 2 else {
            if let last = points.last { path.addLine(to: last) }
            return
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: control)
        }
        path.addLine(to: points[points.count - 1])
    }
}
