import AppKit
import SendpointDomain
import SwiftUI

struct CaptureView: View {
    @Bindable var model: CaptureController

    @State private var focusRequest = 0

    private let palette = OverlayPalette.dark
    private var fontSize: CGFloat { CGFloat(model.transcriptionPreviewFontSize) }
    private var paperOpacity: Double { Double(model.transcriptionPreviewOpacity) / 100 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: VoiceCaptureLayout.cardFooterGap) {
            noteEditor
            HStack(spacing: Spacing.md) {
                CaptureStackLabel(model: model, mode: .text, ink: palette.ink)
                CaptureTether(text: tether, ink: palette.ink)
                Spacer(minLength: 8)
                saveStatus
            }
            .font(.uiBody)
            .frame(height: VoiceCaptureLayout.cardFooterHeight)
        }
        .padding(.horizontal, VoiceCaptureLayout.cardPaddingX)
        .padding(.top, VoiceCaptureLayout.cardPaddingTop)
        .padding(.bottom, VoiceCaptureLayout.cardPaddingBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(palette.paper.opacity(paperOpacity)))
        .overlay(shape.strokeBorder(palette.rim, lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .animation(Motion.springy, value: tether)
        .onAppear { focusRequest += 1 }
        .onChange(of: model.state.session?.context) { _, context in
            guard context != nil else { return }
            focusRequest += 1
        }
        .onChange(of: model.state.session?.destinationPicker) { previous, current in
            if previous == .open, current == .closed, !model.isNoteFrozen {
                focusRequest += 1
            }
        }
    }

    private var tether: String? {
        guard let text = model.captured?.text else { return nil }
        return VoiceOverlayCopy.tether(for: text)
    }

    private var noteEditor: some View {
        NoteEditor(
            text: $model.note,
            placeholder: "Add a note…",
            fontSize: fontSize,
            ink: NSColor(palette.ink),
            isEditable: !model.isNoteFrozen,
            focusRequest: focusRequest,
            onSave: { model.send(.save) },
            onDiscard: { model.send(.dismiss) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.state.session?.phase {
        case .editing where model.state.session?.saveAwaitsSelection == true, .saving:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Saving")
        case let .saveFailed(_, message, retryable):
            Text(message)
                .font(.ui(11.5, weight: .medium))
                .foregroundStyle(palette.amber)
                .lineLimit(1)
                .truncationMode(.tail)
            if retryable {
                QuietButton("Retry") { model.send(.retry) }
            } else {
                QuietButton("Discard") { model.send(.dismiss) }
            }
        default: EmptyView()
        }
    }
}
