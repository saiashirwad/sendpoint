import AppKit
import SendpointDomain
import SwiftUI

/// The one surface for stacks: a searchable list with the highlighted stack's
/// notes previewed beside it, and the same notes opened full-width with →.
struct StackPaletteView: View {
    @Bindable var model: StackPaletteModel
    @FocusState private var focus: PaletteField?
    @Environment(\.colorScheme) private var colorScheme

    static let minimumSize = CGSize(width: 780, height: 460)
    private let stackColumnWidth: CGFloat = 300
    private let rowHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = model.state.problem {
                HStack {
                    Text(message).foregroundStyle(.red)
                    if case .failed(_, _, true) = model.state.interaction {
                        Button("Retry") { model.send(.retry) }
                    } else if case .failed = model.state.interaction {
                        Button("Dismiss") { model.send(.cancelEdit) }
                    }
                }.padding(12)
            } else if let error = model.store.error {
                Divider()
                errorRow(error)
            }
            Divider()
            footer
        }
        .frame(
            minWidth: Self.minimumSize.width, maxWidth: .infinity,
            minHeight: Self.minimumSize.height, maxHeight: .infinity
        )
        .background(PaletteTint.surface(colorScheme))
        .overlay { overlayMenu }
        .clipShape(RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        )
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.async { focus = .search }
        }
        .onChange(of: model.state.focusRequest.generation) {
            // The target field may be created by the same update; focus it
            // once it exists.
            let field = model.state.focusRequest.field
            DispatchQueue.main.async { focus = field }
        }
        .onChange(of: focus) { old, new in
            if case let .note(id) = new {
                model.send(.noteFocus(id))
            } else if case .note = old {
                model.send(.noteFocus(nil))
            }
        }

    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            if case .notes = model.state.level, let session = model.projection.shownSession {
                Button {
                    model.send(.perform(.backToStacks))
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text(session.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(PaletteTint.chip))
                    .foregroundStyle(Color.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("All stacks (←)")
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextField(searchPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focus, equals: .search)
                .disabled(model.state.inlineEdit != nil || model.state.overlay != nil)

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            templateButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    private var searchPlaceholder: String {
        switch model.state.level {
        case .stacks: return "Switch to or create a stack"
        case .notes: return "Search notes"
        }
    }

    private var templateButton: some View {
        Button {
            model.send(.toggleOverlay(.templates))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.projection.activeProfile.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(model.state.overlay == .templates ? 0.12 : 0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Template used when copying (⌘P)")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state.level {
        case .stacks:
            HStack(spacing: 0) {
                stackColumn
                    .frame(width: stackColumnWidth)
                Divider()
                previewPane
            }
        case .notes:
            notesPane
        }
    }

    private var stackColumn: some View {
        let listing = model.projection.stackListing
        return VStack(spacing: 0) {
            if let undo = model.projection.facts.undo {
                undoBanner(undo)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(listing.sessions.enumerated()), id: \.element.id) { index, session in
                            stackRow(session, position: index)
                                .id(QuickSwitchRow.session(session.id))
                        }
                        if case .createStack = model.state.inlineEdit {
                            inlineCreateRow
                        } else if let name = listing.creatableName {
                            createRow(name)
                                .id(QuickSwitchRow.create(name))
                        }
                        if listing.isEmpty {
                            Text("No stacks match “\(model.query.trimmingCharacters(in: .whitespaces))”.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: rowHeight)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.state.stackState.highlight) {
                    guard let highlight = model.state.stackState.highlight else { return }
                    proxy.scrollTo(highlight, anchor: nil)
                }
            }
        }
    }

    private func undoBanner(_ undo: SessionUndoFacts) -> some View {
        Button {
            model.send(.perform(.undoClear))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                Text(undo.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Keycap("⌘Z")
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(PaletteTint.hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Put the cleared notes back")
    }

    private func stackRow(_ session: SessionItemFacts, position: Int) -> some View {
        let isHighlighted = model.state.stackState.highlight == .session(session.id)
        var isRenaming = false
        if case let .renameStack(id, _, _) = model.state.inlineEdit, id == session.id { isRenaming = true }
        return PaletteRow(
            isHighlighted: isHighlighted,
            onSelect: { model.send(.chooseStack(session.id)) },
            onActivate: { model.send(.perform(.switchToStack(session.id))) }
        ) {
            HStack(spacing: 10) {
                if isRenaming {
                    inlineNameField(field: .rename(session.id), placeholder: "Stack name")
                } else {
                    Text(session.name)
                        .font(.system(size: 14, weight: session.isCurrent ? .semibold : .medium))
                        .lineLimit(1)
                        .accessibilityLabel(session.isCurrent ? "\(session.name), current" : session.name)
                }

                Spacer(minLength: 8)

                if position < 9, !isRenaming {
                    Text("⌘\(position + 1)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .opacity(isHighlighted ? 1 : 0.7)
                }

                Text("\(session.annotationCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(session.annotationCount == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 18, alignment: .trailing)
                    .accessibilityLabel(session.countLabel)
            }
        }
        .foregroundStyle(Color.primary)
        .frame(height: rowHeight)
    }

    private func createRow(_ name: String) -> some View {
        let isHighlighted = model.state.stackState.highlight == .create(name)
        return PaletteRow(
            isHighlighted: isHighlighted,
            onSelect: { model.send(.chooseCreate(name)) },
            onActivate: { model.send(.perform(.createStack(name))) }
        ) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                (Text("Create ") + Text("“\(name)”").fontWeight(.semibold))
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Keycap(isHighlighted ? "↩" : "⌘↩")
            }
        }
        .foregroundStyle(Color.primary)
        .frame(height: rowHeight)
    }

    private var inlineCreateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            inlineNameField(field: .create, placeholder: "New stack name")
            Spacer(minLength: 8)
            Keycap("↩")
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PaletteTint.selection)
        )
    }

    private func inlineNameField(field: PaletteField, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(
                placeholder,
                text: Binding(
                    get: { (model.state.inlineEdit?.text ?? "") },
                    set: { model.send(.editText($0)) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .focused($focus, equals: field)
            if let problem = model.state.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Preview (stacks level)

    @ViewBuilder
    private var previewPane: some View {
        if case let .create(name) = model.state.stackState.highlight {
            placeholder(
                symbol: "plus.rectangle.on.folder",
                title: "Create “\(name)”",
                detail: "Press ↩ to make it and switch to it."
            )
        } else if let session = model.projection.shownSession {
            noteCards(session: session, interactive: false)
        } else {
            placeholder(symbol: "square.stack.3d.up", title: "No stack selected", detail: nil)
        }
    }

    // MARK: - Notes (drilled in)

    @ViewBuilder
    private var notesPane: some View {
        if let session = model.projection.shownSession {
            noteCards(session: session, interactive: true)
        } else {
            placeholder(symbol: "square.stack.3d.up", title: "That stack is gone", detail: nil)
        }
    }

    @ViewBuilder
    private func noteCards(session: Session, interactive: Bool) -> some View {
        let listing = model.projection.noteListing
        let wasCleared = model.projection.facts.undo?.sessionID == session.id
        if session.entries.isEmpty && wasCleared, let undo = model.projection.facts.undo {
            VStack(spacing: 14) {
                placeholder(
                    symbol: "tray",
                    title: "Stack cleared",
                    detail: "\(undo.annotationCount) note\(undo.annotationCount == 1 ? "" : "s") set aside."
                )
                .frame(maxHeight: 180)
                Button {
                    model.send(.perform(.undoClear))
                } label: {
                    HStack(spacing: 6) {
                        Text("Undo Clear")
                        Keycap("⌘Z")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.entries.isEmpty {
            emptyState
        } else if listing.isEmpty {
            placeholder(
                symbol: "magnifyingglass",
                title: "No notes match “\(model.query.trimmingCharacters(in: .whitespaces))”",
                detail: nil
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // A plain stack: stacks hold a handful of notes, and
                    // scrollTo inside a lazy stack of variable-height text
                    // can spin the layout engine.
                    VStack(spacing: 2) {
                        ForEach(Array(listing.entries.enumerated()), id: \.element.id) { index, entry in
                            let position = session.entries.firstIndex(where: { $0.id == entry.id }) ?? index
                            NoteCard(
                                index: position,
                                entry: entry,
                                isHighlighted: interactive && model.projection.highlightedNoteID == entry.id,
                                isEditing: interactive && model.state.inlineEdit?.noteID == entry.id,
                                interactive: interactive,
                                draft: Binding(
                                    get: {
                                        model.state.inlineEdit?.noteID == entry.id ? (model.state.inlineEdit?.text ?? "") : entry.note
                                    },
                                    set: { model.send(.editText($0)) }
                                ),
                                focus: $focus,
                                onSelect: { model.send(.chooseNote(entry.id)) },
                                onEdit: { model.send(.perform(.editNote(entry.id))) },
                                onDelete: { model.send(.perform(.deleteNote(entry.id))) }
                            )
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.projection.highlightedNoteID) {
                    guard let id = model.projection.highlightedNoteID else { return }
                    proxy.scrollTo(id, anchor: nil)
                }
                .onAppear {
                    if let id = model.projection.highlightedNoteID { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.quaternary)

            VStack(spacing: 5) {
                Text("Nothing captured yet")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 5) {
                    Text(model.settings.voiceMode.title)
                    Keycap(model.settings.voiceCaptureCombo.displayString, size: 12)
                    Text(model.settings.voiceMode == .hold
                        ? "to speak, then release to save"
                        : "to start, then press again to save")
                }
                HStack(spacing: 5) {
                    Text("Or press")
                    Keycap(model.settings.captureCombo.displayString, size: 12)
                    Text("to type a note about selected text")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.quaternary)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let flash = model.state.flash {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                    Text(flash.text)
                }
                .font(.caption.weight(.medium))
                .transition(.opacity)
            } else {
                Text(footerContext)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let primary = model.projection.primaryAction {
                Button {
                    model.send(.perform(primary.action))
                } label: {
                    HStack(spacing: 6) {
                        Text(primary.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Keycap(primary.keys)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 14)

            Button {
                model.send(.toggleOverlay(.actions))
            } label: {
                HStack(spacing: 6) {
                    Text("Actions")
                        .font(.system(size: 12, weight: .medium))
                    Keycap("⌘K")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .animation(.easeOut(duration: 0.15), value: model.state.flash?.generation)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private var footerContext: String {
        switch model.state.level {
        case .stacks:
            let count = model.projection.facts.sessions.count
            return "\(count) stack\(count == 1 ? "" : "s") · ↑↓ move · → open · esc close"
        case .notes:
            let count = model.projection.shownSession?.entries.count ?? 0
            let name = model.projection.shownSession?.name ?? ""
            return "\(name) · \(count) note\(count == 1 ? "" : "s") · ↑↓ move · ⌥↑↓ reorder · ← back"
        }
    }

    private func errorRow(_ error: AnnotationStoreError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(annotationStoreErrorMessage(error))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if model.store.hasPendingMutations {
                Button("Retry") { model.send(.retry) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Overlay menus

    @ViewBuilder
    private var overlayMenu: some View {
        if let overlay = model.state.overlay {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { model.send(.closeOverlay) }
                Group {
                    switch overlay {
                    case .actions: actionsMenu
                    case .templates: templatesMenu
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 44)
            }
            .transition(.opacity)
        }
    }

    private var actionsMenu: some View {
        let items = model.projection.filteredActionItems
        return OverlayPanel(
            title: "Actions",
            emptyText: "No matching actions",
            isEmpty: items.isEmpty,
            highlight: model.state.overlayHighlight,
            query: $model.overlayQuery,
            focus: $focus
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isHighlighted = index == model.state.overlayHighlight
                OverlayRow(isHighlighted: isHighlighted, onHover: { model.send(.overlayHighlight(index)) }) {
                    model.send(.perform(item.action))
                } content: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Keycap(item.keys)
                    }
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                }
                .id(index)
            }
        }
    }

    private var templatesMenu: some View {
        let profiles = model.projection.filteredProfiles
        return OverlayPanel(
            title: "Copy with template",
            emptyText: "No matching templates",
            isEmpty: profiles.isEmpty,
            highlight: model.state.overlayHighlight,
            query: $model.overlayQuery,
            focus: $focus
        ) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                let isHighlighted = index == model.state.overlayHighlight
                let isActive = profile.id == model.settings.activeProfileID
                OverlayRow(isHighlighted: isHighlighted, onHover: { model.send(.overlayHighlight(index)) }) {
                    model.send(.selectProfile(profile.id))
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                            .foregroundStyle(.primary)
                            .opacity(isActive ? 1 : 0)
                        Text(profile.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if profile.clearSessionAfterExport {
                            Text("clears after copy")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(Color.primary)
                }
                .id(index)
            }
        }
    }
}

// MARK: - Pieces

/// The palette's whole color story: a solid sheet, near-black or paper-white,
/// with every state drawn as a grey wash of the text color so it reads the
/// same in either appearance.
private enum PaletteTint {
    static let cornerRadius: CGFloat = 16

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.09) : .white
    }
    /// A hairline edge so the sheet separates from whatever sits behind it.
    static func rim(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.12 : 0.08)
    }
    /// Raised surface for the ⌘K and template menus.
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.14) : Color(white: 0.985)
    }
    /// Highlighted row or menu item.
    static let selection = Color.primary.opacity(0.10)
    /// Highlighted note: a little quieter, so a tall block of text does not glare.
    static let noteSelection = Color.primary.opacity(0.06)
    /// Pointer resting on a row.
    static let hover = Color.primary.opacity(0.04)
    /// Small filled chips: the back button and note numbers.
    static let chip = Color.primary.opacity(0.08)
    /// Ring around the note being edited.
    static let editing = Color.primary.opacity(0.35)
    /// The rule beside a captured passage.
    static let quoteRule = Color.primary.opacity(0.22)
}

/// A palette row: flat by default, washed with the accent when highlighted.
/// One click highlights it, a second click on the same row runs it.
private struct PaletteRow<Content: View>: View {
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? PaletteTint.selection : hovering ? PaletteTint.hover : Color.clear)
            )
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { onActivate() }
            .onTapGesture { onSelect() }
    }
}

/// One captured passage with its note, drawn the same whether previewed or
/// opened; only the opened card takes a highlight and edits.
private struct NoteCard: View {
    let index: Int
    let entry: SendpointDomain.Annotation
    let isHighlighted: Bool
    let isEditing: Bool
    let interactive: Bool
    @Binding var draft: String
    var focus: FocusState<PaletteField?>.Binding
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var quote: String {
        guard case let .selection(quote) = entry.subject else { return "" }
        return quote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(PaletteTint.chip))

                AppIcon(application: entry.provenance.application)

                Text(entry.provenance.application.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let window = entry.provenance.windowTitle?.nonblank {
                    Text(window)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if entry.provenance.url != nil, interactive {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("Open source (⌘O)")
                }

                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)

                if interactive {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(PaletteTint.hover))
                    }
                    .buttonStyle(.plain)
                    .help("Delete note (⌘⌫)")
                    .accessibilityLabel("Delete note \(index + 1)")
                    .opacity(hovering || isHighlighted ? 1 : 0)
                }
            }

            if !quote.isEmpty {
                QuotedPassage(text: quote)
            }

            // Only the note being edited is a text field. Every other note is
            // plain text, so ↑↓ never re-measures a column of editors; ↩ or
            // a click on the text swaps the editor in.
            if isEditing {
                TextField(
                    quote.isEmpty ? "Write a thought…" : "Add a note about this passage…",
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.body)
                .lineSpacing(2)
                .lineLimit(1...8)
                .focused(focus, equals: .note(entry.id))
            } else if let note = entry.note.nonblank {
                Text(note)
                    .font(.body)
                    .lineSpacing(2)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if interactive { onEdit() } }
            } else {
                Text(interactive ? "Add a note…" : "No note")
                    .font(.body)
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if interactive { onEdit() } }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        // Notes sit on one continuous surface; the highlighted one simply
        // lifts to a soft grey.
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? PaletteTint.noteSelection : hovering && interactive ? PaletteTint.hover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PaletteTint.editing, lineWidth: 1)
                .opacity(isEditing ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { if interactive { onSelect() } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }
}

/// A captured passage set as a quiet quotation: a thin rule down the left
/// and the text a step softer than the note it belongs to.
private struct QuotedPassage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .lineSpacing(2)
            .lineLimit(6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(PaletteTint.quoteRule)
                    .frame(width: 2)
            }
    }
}

/// The icon of the app a note came from, looked up once per bundle and
/// cached. Apps we cannot find get a neutral glyph rather than nothing, so
/// the provenance row keeps its shape.
private struct AppIcon: View {
    let application: ApplicationIdentity

    /// Misses are cached too, so an uninstalled app costs one lookup, not one
    /// per render.
    @MainActor private static var cache: [String: NSImage?] = [:]

    var body: some View {
        Group {
            if let image = Self.icon(for: application) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    @MainActor
    private static func icon(for application: ApplicationIdentity) -> NSImage? {
        guard let bundleID = application.bundleID?.nonblank else { return nil }
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            let icon = NSWorkspace.shared.icon(forFile: $0.path)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
        cache[bundleID] = image
        return image
    }
}

/// The floating menu in the corner: a list of rows and a filter field below
/// them, the way Raycast lays out its action panel.
private struct OverlayPanel<Rows: View>: View {
    let title: String
    let emptyText: String
    let isEmpty: Bool
    /// Index of the highlighted row; the list scrolls to keep it in view.
    let highlight: Int
    @Binding var query: String
    var focus: FocusState<PaletteField?>.Binding
    @ViewBuilder let rows: () -> Rows
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        rows()
                        if isEmpty {
                            Text(emptyText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlight) { proxy.scrollTo(highlight) }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(focus, equals: .overlay)
                Keycap("esc")
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PaletteTint.raised(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 22, y: 10)
    }
}

private struct OverlayRow<Content: View>: View {
    let isHighlighted: Bool
    let onHover: () -> Void
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? PaletteTint.selection : Color.clear)
        )
        .onHover { if $0 { onHover() } }
    }
}
