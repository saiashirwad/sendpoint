import SendpointDomain
import SwiftUI

/// The palette's note pane: the highlighted stack's notes as cards, with
/// the scroll-landing modifiers that keep keyboard movement in view.
/// Takes the shell-threaded projection plus small scalars; the shared
/// NoteFrames instance stays owned by the shell and is passed through.
struct NoteListView: View {
    let projection: PaletteProjection
    let stackHighlight: QuickSwitchRow?
    let query: String
    let focusedPane: PalettePane
    let inlineEdit: PaletteEdit?
    let noteNamespace: Namespace.ID
    let focus: FocusState<PaletteField?>.Binding
    let noteFrames: NoteFrames
    let onEvent: (PaletteEvent) -> Void

    var body: some View {
        notePane(projection)
    }

    @ViewBuilder
    private func notePane(_ projection: PaletteProjection) -> some View {
        if case let .create(name) = stackHighlight {
            placeholder(title: "Create “\(name)”", detail: "Press ↩ to make it and switch to it.")
        } else if let stack = projection.shownStack {
            noteCards(stack: stack, projection: projection)
        } else {
            placeholder(title: "No stack selected", detail: nil)
        }
    }

    @ViewBuilder
    private func noteCards(stack: Stack, projection: PaletteProjection) -> some View {
        let listing = projection.noteListing
        let wasCleared = projection.facts.undo?.stackID == stack.id
        if stack.notes.isEmpty && wasCleared, let undo = projection.facts.undo {
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
                    // A plain stack: stacks hold a handful of notes, and
                    // lazy stacks of variable-height text re-measure on
                    // every move.
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
            // Keep focus grouping stable across inline edits; keys are
            // routed by the window monitor, not by this section.
            .focusSection()
            .coordinateSpace(name: StackPaletteView.notesSpace)
            .onPreferenceChange(NoteFramesKey.self) { frames in
                noteFrames.frames.merge(frames) { $1 }
                // A landing stays armed until a fresh frame shows the note
                // at the bottom edge: text lays out over a few passes, and
                // a frame measured early is shorter than the note ends up.
                noteFrames.settle()
            }
            .onChange(of: projection.highlightedNoteID) {
                // Keyboard movement brings the highlighted note into view,
                // and only when it is cut off, so the list never jumps
                // under a note already on screen.
                guard focusedPane == .notes,
                      let id = projection.highlightedNoteID else { return }
                guard let frame = noteFrames.frames[id] else {
                    noteFrames.landing = id
                    return
                }
                if let anchor = noteRevealAnchor(frame: frame, viewportHeight: noteFrames.scroll.viewportHeight) {
                    noteFrames.scroll.reveal(frame, anchor: anchor, animated: true)
                }
            }
            .onChange(of: stack.id) {
                // Arrowing the sidebar lands each stack's preview at its
                // newest note.
                guard let id = listing.notes.last?.id else { return }
                noteFrames.land(on: id)
            }
            .onAppear {
                // The newest note is the landing spot when nothing is
                // highlighted yet.
                guard let id = projection.highlightedNoteID ?? listing.notes.last?.id else { return }
                noteFrames.land(on: id)
            }
        }
    }

    private func noteCard(_ entry: SendpointDomain.Note, highlightedNoteID: UUID?) -> some View {
        NoteCard(
            entry: entry,
            isHighlighted: highlightedNoteID == entry.id,
            isDimmed: focusedPane != .notes,
            isEditing: inlineEdit?.noteID == entry.id,
            draft: Binding(
                get: {
                    inlineEdit?.noteID == entry.id ? (inlineEdit?.text ?? "") : entry.body
                },
                set: { onEvent(.editText($0)) }
            ),
            focus: focus,
            namespace: noteNamespace,
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
