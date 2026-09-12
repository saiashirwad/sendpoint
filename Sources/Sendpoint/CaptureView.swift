import AppKit
import SendpointDomain
import SwiftUI

/// The typed capture draft and its inline save recovery controls.
struct CaptureView: View {
    @Bindable var model: CaptureController

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var noteFocused: Bool
    @State private var quoteHeight: CGFloat = 0

    /// Keeps the source visible without letting a long selection push the
    /// editor actions below the panel's compact resize floor.
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
                Divider()
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

            Divider()
            if case .editing = model.state.session?.phase, !model.isNoteFrozen {
                footer
            } else {
                saveStatus
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaletteTint.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.async { noteFocused = true }
        }
        // The panel is kept between notes, so each new capture asks for
        // focus itself rather than relying on a first appearance.
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
            Button {
                model.send(.dismiss)
            } label: {
                ActionLabel(title: "Discard", shortcut: "esc")
            }
            .foregroundStyle(.secondary)

            Divider().frame(height: 14)

            Button {
                model.send(.save)
            } label: {
                ActionLabel(title: "Save", shortcut: "⌘↩")
            }
            .disabled(model.note.nonblank == nil)
        }
        .buttonStyle(.plain)
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
        .overlayScrollers()
        .frame(height: min(max(quoteHeight, 16), quoteMaxHeight))
        .onPreferenceChange(HeightKey.self) { quoteHeight = $0 }
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.note)
                .font(.body)
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                // NSTextView supplies a five-point text-container inset.
                .padding(.horizontal, -5)
                .focused($noteFocused)
                .frame(minHeight: 72, idealHeight: 108, maxHeight: .infinity)
                .overlayScrollers()
                .disabled(model.isNoteFrozen)

            if model.note.isEmpty {
                Text("Add a note…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .editing, .none:
            EmptyView()
        case let .saveFailed(_, message, retryable, missing):
            statusRow(message: message, color: .red) {
                if retryable {
                    Button("Retry") { model.send(.retry) }.buttonStyle(.borderedProminent)
                } else {
                    if missing {
                        Button("Save to Current Stack") { model.saveToCurrentStack() }
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

private struct ActionLabel: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Keycap(shortcut)
        }
        .contentShape(Rectangle())
    }
}
