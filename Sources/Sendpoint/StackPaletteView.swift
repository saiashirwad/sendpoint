import AppKit
import SendpointDomain
import SwiftUI

/// The one surface for stacks: a stack sidebar beside the highlighted
/// stack's notes. Tab and the arrows move the keyboard between the panes;
/// both are always drawn, and the unfocused one dims its highlight.
///
/// Thin shell: this file owns the model binding, focus state, highlight
/// namespaces, and the shared NoteFrames instance, computes the single
/// projection read per body, and composes the extracted section views.
/// All palette chrome lives in the Palette* files; behavior is identical.
struct StackPaletteView: View {
    @Bindable var model: StackPaletteModel
    @FocusState private var focus: PaletteField?

    static let minimumSize = CGSize(width: 780, height: 460)
    private let rowHeight: CGFloat = 36
    /// Where each note sits in the list's viewport. Owned by the window
    /// controller, so the frames outlive view identity. A plain class, so
    /// the frames can update on every scroll without redrawing the palette.
    let noteFrames: NoteFrames
    static let notesSpace = "notes"
    /// One highlight pill per pane and one current-stack dot, each a single
    /// shape that slides between rows instead of popping.
    @Namespace private var noteHighlight
    @Namespace private var stackHighlight
    @Namespace private var currentDot

    /// How a highlight pill or the current-stack dot slides to its new row.
    /// File-visible so the pill backgrounds in RowShell/NoteCard and the
    /// per-row dot modifier in StackColumnView can scope the spring to their
    /// own row (StackRow.swift itself is untouched).
    static let travel = Animation.spring(response: 0.18, dampingFraction: 0.92)

    var body: some View {
        let projection = model.projection
        VStack(spacing: 0) {
            PaletteHeaderView(
                projection: projection,
                query: $model.query,
                presentation: model.state.presentation,
                focusedPane: model.state.focusedPane,
                isSearchDisabled: model.state.inlineEdit != nil || model.state.overlay != nil,
                focus: $focus
            )
            Hairline()
            content(projection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.state.presentation != .cycling, let undo = projection.facts.undo {
                Hairline()
                PaletteUndoBanner(undo: undo, onEvent: { model.send($0) })
            }
            if let message = model.state.problem {
                Hairline()
                PaletteProblemRow(
                    message: message,
                    interaction: model.state.interaction,
                    onEvent: { model.send($0) }
                )
            } else if let error = model.store.error {
                Hairline()
                PaletteErrorRow(
                    error: error,
                    hasPendingMutations: model.store.hasPendingMutations,
                    onEvent: { model.send($0) }
                )
            }
            Hairline()
            PaletteFooterView(
                projection: projection,
                presentation: model.state.presentation,
                focusedPane: model.state.focusedPane,
                flash: model.state.flash,
                switchComboLabel: model.shortcuts.switchStackCombo.displayString,
                onEvent: { model.send($0) }
            )
        }
        .frame(
            minWidth: Self.minimumSize.width, maxWidth: .infinity,
            minHeight: Self.minimumSize.height, maxHeight: .infinity
        )
        .background(Backdrop())
        .font(.uiBody)
        .overlay {
            PaletteOverlaysView(
                projection: projection,
                overlay: model.state.overlay,
                highlight: model.state.overlayHighlight,
                overlayQuery: $model.overlayQuery,
                activeTemplateID: model.settings.activeTemplateID,
                focus: $focus,
                onEvent: { model.send($0) }
            )
        }
        .allowsHitTesting(model.state.presentation != .cycling)
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.async { focus = model.state.presentation == .cycling ? nil : .search }
        }
        .onChange(of: model.state.focusRequest.generation) {
            // The target field may be created by the same update; focus it
            // once it exists.
            let field = model.state.focusRequest.field
            DispatchQueue.main.async { focus = model.state.presentation == .cycling ? nil : field }
        }
        .onChange(of: focus) { old, new in
            // Echo guard: the generation writer above assigns focus back
            // from focusRequest, which would otherwise bounce here as a
            // .noteFocus send (and a fresh requestFocus) every time the
            // reducer moves focus. Only a field the reducer did not ask
            // for is reported. (PaletteField's Equatable covers the .note
            // associated values, and the non-optional request field
            // promotes to Optional for the comparison.)
            guard model.state.focusRequest.field != new else { return }
            if case let .note(id) = new {
                model.send(.noteFocus(id))
            } else if case .note = old {
                model.send(.noteFocus(nil))
            }
        }
    }

    private func content(_ projection: PaletteProjection) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                StackColumnView(
                    projection: projection,
                    query: model.query,
                    highlight: model.state.stackState.highlight,
                    focusedPane: model.state.focusedPane,
                    presentation: model.state.presentation,
                    inlineEdit: model.state.inlineEdit,
                    rowHeight: rowHeight,
                    stackNamespace: stackHighlight,
                    dotNamespace: currentDot,
                    focus: $focus,
                    onEvent: { model.send($0) }
                )
                .frame(width: sidebarWidth(for: proxy.size.width))
                Hairline(axis: .vertical)
                NoteListView(
                    projection: projection,
                    stackHighlight: model.state.stackState.highlight,
                    query: model.query,
                    focusedPane: model.state.focusedPane,
                    inlineEdit: model.state.inlineEdit,
                    noteNamespace: noteHighlight,
                    focus: $focus,
                    noteFrames: noteFrames,
                    onEvent: { model.send($0) }
                )
                .contentShape(Rectangle())
                .onTapGesture { model.send(.focusPane(.notes)) }
            }
        }
    }

    /// A sidebar that stays readable at the minimum width and stops growing
    /// once it is wide enough.
    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.26, 220), 260)
    }
}

/// Note frames in the viewport, written from layout and read on keyboard
/// movement. Not observed: nothing should redraw because a note moved.
final class NoteFrames {
    var frames: [UUID: CGRect] = [:]
    let scroll = ScrollHandle()
    /// A note to bring to the bottom edge as soon as it has a frame.
    var landing: UUID?

    /// Brings a note to the bottom edge, now if its frame is known and again
    /// as the list settles, so a list still being laid out lands there too.
    func land(on id: UUID) {
        landing = id
        settle()
    }

    /// Disarms a pending landing so late settle() retries no-op. Idempotent;
    /// the window controller calls it on every hide and on teardown.
    func disarm() {
        landing = nil
    }

    /// One step of a landing: done when the note sits at the bottom edge,
    /// otherwise scroll there. When the scroll view's content was still too
    /// short to allow it, try again shortly; the height catches up within a
    /// few turns of the run loop.
    func settle(attempt: Int = 0) {
        guard let id = landing, let frame = frames[id] else { return }
        if scroll.isAtBottomEdge(frame) {
            landing = nil
            return
        }
        let reached = scroll.reveal(frame, anchor: .bottom, animated: false)
        guard !reached, attempt < Self.retryDelays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
            self?.settle(attempt: attempt + 1)
        }
    }

    private static let retryDelays: [TimeInterval] = [0.02, 0.05, 0.1, 0.2, 0.4]
}

struct NoteFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
