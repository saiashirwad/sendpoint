import AppKit
import SendpointDomain
import SwiftUI

struct CaptureView: View {
    @Bindable var model: CaptureController

    @FocusState private var noteFocused: Bool

    private let palette = OverlayPalette.dark
    private var paperOpacity: Double { Double(model.transcriptionPreviewOpacity) / 100 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: VoiceCaptureLayout.cardFooterGap) {
            noteEditor
                .padding(.top, -2)
            HStack(spacing: 10) {
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
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tether)
        .onAppear {
            DispatchQueue.main.async { noteFocused = true }
        }
        .onChange(of: model.state.session?.context) { _, context in
            guard context != nil else { return }
            DispatchQueue.main.async { noteFocused = true }
        }
        .onChange(of: model.state.session?.destinationPicker) { previous, current in
            if previous == .open, current == .closed, !model.isNoteFrozen {
                noteFocused = true
            }
        }
    }

    private var tether: String? {
        guard let text = model.captured?.text else { return nil }
        return VoiceOverlayCopy.tether(for: text)
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.note)
                .font(.uiBody)
                .lineSpacing(VoiceCaptureLayout.transcriptLineSpacing)
                .foregroundStyle(palette.ink.opacity(0.92))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .accessibilityLabel("Note")
                .accessibilityAction(named: "Save") { model.send(.save) }
                .accessibilityAction(named: "Discard") { model.send(.dismiss) }
                .focused($noteFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(model.isNoteFrozen)

            if model.note.isEmpty {
                Text("Add a note…")
                    .font(.uiBody)
                    .foregroundStyle(palette.ink.opacity(0.35))
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
