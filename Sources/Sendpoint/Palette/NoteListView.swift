import SendpointDomain
import SwiftUI

struct NoteListView: View {
    let projection: PaletteProjection
    let query: String
    let inlineEdit: PaletteEdit?
    let focus: FocusState<PaletteField?>.Binding
    let noteFrames: NoteFrames
    let onEvent: (PaletteEvent) -> Void

    var body: some View {
        notePane(projection)
    }

    @ViewBuilder
    private func notePane(_ projection: PaletteProjection) -> some View {
        if let stack = projection.shownStack {
            noteCards(stack: stack, projection: projection)
        } else {
            placeholder(title: "Stack unavailable", detail: nil)
        }
    }

    @ViewBuilder
    private func noteCards(stack: Stack, projection: PaletteProjection) -> some View {
        let listing = projection.noteListing
        if stack.notes.isEmpty, let undo = projection.undo {
            VStack(spacing: 18) {
                placeholder(title: "Stack cleared", detail: "\(noteCountLabel(undo.noteCount)) set aside.")
                    .frame(maxHeight: 120)
                QuietButton("Undo", keys: "⌘Z") {
                    onEvent(.perform(.undoClear))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stack.notes.isEmpty {
            emptyState
        } else if listing.isEmpty {
            placeholder(
                title: "No notes match “\(query.trimmingCharacters(in: .whitespaces))”",
                detail: nil
            )
        } else {
            ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(listing.notes.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Hairline().padding(.horizontal, NoteCard.inset)
                            }
                            noteCard(entry, highlightedNoteID: projection.highlightedNoteID)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(ScrollProbe(handle: noteFrames.scroll))
            }
            .focusSection()
            .coordinateSpace(name: StackPaletteView.notesSpace)
            .onPreferenceChange(NoteFramesKey.self) { frames in
                noteFrames.frames.merge(frames) { $1 }
                noteFrames.settle()
            }
            .onChange(of: projection.highlightedNoteID) {
                guard let id = projection.highlightedNoteID else { return }
                guard let frame = noteFrames.frames[id] else {
                    noteFrames.landing = id
                    return
                }
                if let anchor = noteRevealAnchor(frame: frame, viewportHeight: noteFrames.scroll.viewportHeight) {
                    noteFrames.scroll.reveal(frame, anchor: anchor)
                }
            }
            .onChange(of: stack.id) {
                guard let id = listing.notes.last?.id else { return }
                noteFrames.land(on: id)
            }
            .onAppear {
                guard let id = projection.highlightedNoteID ?? listing.notes.last?.id else { return }
                noteFrames.land(on: id)
            }
        }
    }

    private func noteCard(_ entry: SendpointDomain.Note, highlightedNoteID: UUID?) -> some View {
        NoteCard(
            entry: entry,
            isHighlighted: highlightedNoteID == entry.id,
            isEditing: inlineEdit?.noteID == entry.id,
            draft: Binding(
                get: {
                    inlineEdit?.noteID == entry.id ? (inlineEdit?.text ?? "") : entry.body
                },
                set: { onEvent(.editText($0)) }
            ),
            focus: focus,
            onSelect: { onEvent(.chooseNote(entry.id)) },
            onEdit: { onEvent(.perform(.editNote(entry.id))) }
        )
        .equatable()
        .id(entry.id)
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: NoteFramesKey.self,
                value: [entry.id: geometry.frame(in: .named(StackPaletteView.notesSpace))]
            )
        })
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            EmptyStackGlyph()
            Readout("Nothing captured yet")
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(title: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            Readout(title)
            if let detail {
                Text(detail)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
