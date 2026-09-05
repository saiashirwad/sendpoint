import AppKit
import SwiftUI

/// The typed capture draft and its inline save recovery controls.
struct CaptureView: View {
    @Bindable var model: CaptureController

    @FocusState private var noteFocused: Bool
    @State private var quoteHeight: CGFloat = 0

    private let quoteMaxHeight: CGFloat = 150

    private var quote: String {
        (model.captured?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !quote.isEmpty {
                quoteBlock
            }
            noteEditor
            if case .editing = model.state.session?.phase {
                HStack(spacing: 12) {
                    ShortcutHint(keys: "⌘↩", label: "Save")
                    ShortcutHint(keys: "esc", label: "Discard")
                    Spacer()
                }
            }
            saveStatus
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.async { noteFocused = true }
        }
    }

    private var quoteBlock: some View {
        ScrollView {
            Text(quote)
                .font(.callout)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .overlayScrollers()
        .frame(height: min(max(quoteHeight, 32), quoteMaxHeight))
        .insetSurface()
        .onPreferenceChange(HeightKey.self) { quoteHeight = $0 }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.note)
                .font(.body)
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .focused($noteFocused)
                .frame(minHeight: 84)
                .overlayScrollers()
                .disabled(model.isNoteFrozen)

            if model.note.isEmpty {
                Text("Add a note…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .insetSurface(fill: Color(nsColor: .textBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.state.session?.phase {
        case .editing, .none:
            EmptyView()
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case let .saveFailed(_, message, retryable, missing):
            statusRow(message: message, color: .red) {
                if retryable {
                    Button("Retry") { model.send(.retry) }.buttonStyle(.borderedProminent)
                } else {
                    if missing {
                        Button("Save to Current Stack") { model.saveToCurrentSession() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Discard", role: .destructive) { model.send(.dismiss) }
                }
            }
        default: EmptyView()
        }
    }

    private func statusRow<Actions: View>(
        message: String,
        color: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.callout)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
    }
}
