import AppKit
import SendpointDomain
import SwiftUI

struct StackPaletteView: View {
    @Bindable var model: StackPaletteModel
    @FocusState private var focus: PaletteField?

    static let minimumSize = CGSize(width: 560, height: 460)
    let noteFrames: NoteFrames
    static let notesSpace = "notes"
    var body: some View {
        let projection = model.projection
        VStack(spacing: 0) {
            PaletteHeaderView(
                projection: projection,
                query: $model.query,
                isSearchDisabled: model.state.inlineEdit != nil || model.state.overlay != nil,
                focus: $focus,
                onEvent: { model.send($0) }
            )
            Hairline()
            NoteListView(
                projection: projection,
                query: model.query,
                inlineEdit: model.state.inlineEdit,
                focus: $focus,
                noteFrames: noteFrames,
                onEvent: { model.send($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = projection.problem {
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
                flash: model.state.flash,
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
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.async { focus = .search }
        }
        .onChange(of: model.state.focusRequest.generation) {
            let field = model.state.focusRequest.field
            DispatchQueue.main.async { focus = field }
        }
        .onChange(of: focus) { old, new in
            guard model.state.focusRequest.field != new else { return }
            if case let .note(id) = new {
                model.send(.noteFocus(id))
            } else if case .note = old {
                model.send(.noteFocus(nil))
            }
        }
    }
}

final class NoteFrames {
    var frames: [UUID: CGRect] = [:]
    let scroll = ScrollHandle()
    var landing: UUID?

    func land(on id: UUID) {
        landing = id
        settle()
    }

    func disarm() {
        landing = nil
    }

    func settle(attempt: Int = 0) {
        guard let id = landing, let frame = frames[id] else { return }
        if scroll.isAtBottomEdge(frame) {
            landing = nil
            return
        }
        let reached = scroll.reveal(frame, anchor: .bottom)
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
