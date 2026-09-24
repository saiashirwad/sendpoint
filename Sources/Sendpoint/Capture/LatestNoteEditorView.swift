import AppKit
import SwiftUI
import SendpointDomain

struct LatestNoteEditorView: View {
    @Bindable var model: LatestNoteEditor
    @State private var quoteExpanded = true
    private let palette = OverlayPalette.dark

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit latest note").font(.ui(14, weight: .semibold))
                Spacer()
                Text(model.state.draft?.stackName ?? "").foregroundStyle(.secondary)
            }
            if case let .selection(quote) = model.state.draft?.original.subject {
                DisclosureGroup("Original quote", isExpanded: $quoteExpanded) {
                    ScrollView {
                        Text(quote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)
                    .foregroundStyle(.secondary)
                }
            }
            NoteEditor(
                text: $model.text, placeholder: "Note", fontSize: 16,
                ink: NSColor(palette.ink), isEditable: model.isEditable,
                focusRequest: model.focusRequest,
                onSave: { model.send(.save) }, onDiscard: { model.send(.dismiss) }
            )
            .id(model.state.draft?.sessionID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if case let .failed(_, message, pending) = model.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).foregroundStyle(palette.amber)
                    if pending {
                        Text("Your edit is queued. Retry saving before closing.")
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
            HStack {
                if case .confirmingDiscard = model.state {
                    Text("Discard your changes?")
                    Spacer()
                    Button("Keep editing") { model.send(.keepEditing) }
                    Button("Discard", role: .destructive) { model.send(.discard) }
                } else {
                    Button("Cancel") { model.send(.dismiss) }
                        .disabled(model.hasPendingSave)
                    Spacer()
                    if case .saving = model.state {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    } else if case .failed(_, _, pending: true) = model.state {
                        Button("Retry save") { model.send(.retry) }
                    } else {
                        Button("Save  ⌘↩") { model.send(.save) }
                            .disabled(!model.isEditable)
                    }
                }
            }
        }
        .font(.uiBody)
        .padding(22)
        .foregroundStyle(palette.ink)
        .background(RoundedRectangle(cornerRadius: Ink.cornerRadius).fill(palette.paper))
        .overlay(RoundedRectangle(cornerRadius: Ink.cornerRadius).strokeBorder(palette.rim, lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}
