import AppKit
import SendpointDomain
import SwiftUI

struct CaptureView: View {
    @Bindable var model: CaptureController

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var noteFocused: Bool
    @State private var quoteHeight: CGFloat = 0

    private let quoteMaxHeight: CGFloat = 80

    private var quote: String {
        model.captured?.text.nonblank ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.state.session != nil {
                HStack {
                    CaptureDestinationButton(model: model, mode: .text, showsIcon: true)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
                Hairline()
            }

            VStack(alignment: .leading, spacing: 12) {
                if !quote.isEmpty {
                    quoteBlock
                }
                noteEditor
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Hairline()
            if case .editing = model.state.session?.phase, !model.isNoteFrozen {
                footer
            } else {
                saveStatus
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper(colorScheme))
        .font(.uiBody)
        .clipShape(RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous)
                .strokeBorder(Ink.rim(colorScheme), lineWidth: 1)
        }
        .ignoresSafeArea()
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

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            QuietButton("Discard", keys: "esc") {
                model.send(.dismiss)
            }

            Hairline(axis: .vertical)
                .frame(height: 14)

            InkButton("Save", keys: "⌘↩") {
                model.send(.save)
            }
            .disabled(model.note.nonblank == nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private var quoteBlock: some View {
        ScrollView {
            QuotedPassage(text: quote)
                .textSelection(.enabled)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .frame(height: min(max(quoteHeight, 16), quoteMaxHeight))
        .onPreferenceChange(HeightKey.self) { quoteHeight = $0 }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.note)
                .font(.uiBody)
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .accessibilityLabel("Note")
                .focused($noteFocused)
                .frame(minHeight: 72, idealHeight: 108, maxHeight: .infinity)
                .disabled(model.isNoteFrozen)

            if model.note.isEmpty {
                Text("Add a note…")
                    .font(.uiBody)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.state.session?.phase {
        case .editing where model.state.session?.saveAwaitsSelection == true, .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .editing, .none:
            EmptyView()
        case let .saveFailed(_, message, retryable):
            statusRow(message: message) {
                HStack(spacing: 8) {
                    if retryable {
                        InkButton("Retry") { model.send(.retry) }
                    } else {
                        QuietButton("Discard") { model.send(.dismiss) }
                    }
                }
            }
        default: EmptyView()
        }
    }

    private func statusRow<Actions: View>(
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.uiCallout)
                .foregroundStyle(Ink.amber(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
    }
}
