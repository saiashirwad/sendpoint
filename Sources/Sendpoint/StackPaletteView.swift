import AppKit
import SendpointDomain
import SwiftUI

/// The one surface for stacks: a stack sidebar beside the highlighted
/// stack's notes. Tab and the arrows move the keyboard between the panes;
/// both are always drawn, and the unfocused one dims its highlight.
struct StackPaletteView: View {
    @Bindable var model: StackPaletteModel
    @FocusState private var focus: PaletteField?
    @Environment(\.colorScheme) private var colorScheme

    static let minimumSize = CGSize(width: 780, height: 460)
    private let rowHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.state.presentation != .cycling, let undo = model.projection.facts.undo {
                Divider()
                undoBanner(undo)
            }
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if model.state.presentation == .cycling {
                Text("Switch stack").font(.system(size: 17))
                Spacer()
            } else {
                TextField(model.projection.searchPlaceholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focus, equals: .search)
                    .disabled(model.state.inlineEdit != nil || model.state.overlay != nil)
            }

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

    private var templateButton: some View {
        Button {
            model.send(.toggleOverlay(.templates))
        } label: {
            HStack(spacing: 6) {
                Text("Copy as \(model.projection.activeTemplate.name)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Keycap("⌘P")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Template used when copying (⌘P)")
    }

    // MARK: - Content

    private var content: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                stackColumn
                    .frame(width: sidebarWidth(for: proxy.size.width))
                Divider()
                notePane
                    .contentShape(Rectangle())
                    .onTapGesture { model.send(.focusPane(.notes)) }
            }
        }
    }

    /// A sidebar that stays readable at the minimum width and stops growing
    /// once it is wide enough.
    private func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * 0.25, 220), 260)
    }

    private var stackColumn: some View {
        let listing = model.projection.stackListing
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(listing.stacks.enumerated()), id: \.element.id) { index, stack in
                            stackRow(stack, position: index)
                                .id(QuickSwitchRow.stack(stack.id))
                        }
                        if let name = listing.creatableName {
                            createRow(name)
                                .id(QuickSwitchRow.create(name))
                        }
                        if listing.isEmpty {
                            Text("No stacks match “\(model.query.trimmingCharacters(in: .whitespaces))”.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: rowHeight)
                        }
                    }
                }
                .onChange(of: model.state.stackState.highlight) {
                    guard let highlight = model.state.stackState.highlight else { return }
                    proxy.scrollTo(highlight, anchor: nil)
                }
            }
            Divider()
            newStackRow
        }
        .contentShape(Rectangle())
        .onTapGesture { model.send(.focusPane(.stacks)) }
    }

    /// The pinned row at the foot of the sidebar: a click, ⌘N, or a typed
    /// name all lead here. It swaps to the name field while creating.
    @ViewBuilder
    private var newStackRow: some View {
        if case .createStack = model.state.inlineEdit {
            inlineCreateRow
        } else {
            Button {
                model.send(.perform(.newStack))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("New stack")
                        .font(.system(size: 14))
                    Spacer(minLength: 8)
                    Keycap("⌘N")
                }
                .padding(.horizontal, 16)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Create a stack (⌘N)")
        }
    }

    private func undoBanner(_ undo: StackUndoFacts) -> some View {
        HStack(spacing: 8) {
            Text(undo.notification)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(undo.notification)
            Button {
                model.send(.perform(.undoClear))
            } label: {
                HStack(spacing: 6) {
                    Text("Undo")
                        .font(.system(size: 12, weight: .medium))
                    Keycap("⌘Z")
                }
            }
            .buttonStyle(.plain)
            .help("Put the cleared notes back")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(PaletteTint.hover)
    }

    private func stackRow(_ stack: StackItemFacts, position: Int) -> some View {
        let isHighlighted = model.state.stackState.highlight == .stack(stack.id)
        var isRenaming = false
        if case let .renameStack(id, _, _) = model.state.inlineEdit, id == stack.id { isRenaming = true }
        return PaletteRow(
            isHighlighted: isHighlighted,
            isDimmed: model.state.focusedPane != .stacks,
            onSelect: { model.send(.chooseStack(stack.id)) },
            onActivate: { model.send(.perform(.switchToStack(stack.id))) }
        ) {
            if isRenaming {
                StackRow(
                    noteCount: stack.noteCount,
                    position: position,
                    showsDigit: false
                ) {
                    inlineNameField(field: .rename(stack.id), placeholder: "Stack name")
                }
            } else {
                StackRow(
                    name: stack.name,
                    noteCount: stack.noteCount,
                    isCurrent: stack.isCurrent,
                    position: position,
                    showsDigit: true
                )
            }
        }
        .frame(height: rowHeight)
    }

    private func createRow(_ name: String) -> some View {
        let isHighlighted = model.state.stackState.highlight == .create(name)
        return PaletteRow(
            isHighlighted: isHighlighted,
            isDimmed: model.state.focusedPane != .stacks,
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
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
        .background(Rectangle().fill(PaletteTint.selection))
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

    // MARK: - Notes

    @ViewBuilder
    private var notePane: some View {
        if case let .create(name) = model.state.stackState.highlight {
            placeholder(
                symbol: "plus.rectangle.on.folder",
                title: "Create “\(name)”",
                detail: "Press ↩ to make it and switch to it."
            )
        } else if let stack = model.projection.shownStack {
            noteCards(stack: stack)
        } else {
            placeholder(symbol: "square.stack.3d.up", title: "No stack selected", detail: nil)
        }
    }

    @ViewBuilder
    private func noteCards(stack: Stack) -> some View {
        let listing = model.projection.noteListing
        let wasCleared = model.projection.facts.undo?.stackID == stack.id
        if stack.notes.isEmpty && wasCleared, let undo = model.projection.facts.undo {
            VStack(spacing: 14) {
                placeholder(
                    symbol: "tray",
                    title: "Stack cleared",
                    detail: "\(noteCountLabel(undo.noteCount)) set aside."
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
        } else if stack.notes.isEmpty {
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
                    VStack(spacing: 0) {
                        ForEach(listing.notes, id: \.id) { entry in
                            NoteCard(
                                entry: entry,
                                isHighlighted: model.projection.highlightedNoteID == entry.id,
                                isDimmed: model.state.focusedPane != .notes,
                                isEditing: model.state.inlineEdit?.noteID == entry.id,
                                draft: Binding(
                                    get: {
                                        model.state.inlineEdit?.noteID == entry.id ? (model.state.inlineEdit?.text ?? "") : entry.body
                                    },
                                    set: { model.send(.editText($0)) }
                                ),
                                focus: $focus,
                                onSelect: { model.send(.chooseNote(entry.id)) },
                                onEdit: { model.send(.perform(.editNote(entry.id))) }
                            )
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: model.projection.highlightedNoteID) {
                    // The newest note is the landing spot whenever the shown
                    // stack changes; keyboard movement just brings the
                    // highlighted note into view.
                    guard model.state.focusedPane == .notes,
                          let id = model.projection.highlightedNoteID else { return }
                    proxy.scrollTo(id, anchor: nil)
                }
                .onChange(of: stack.id) {
                    // Arrowing the sidebar lands each stack's preview at its
                    // newest note.
                    guard let id = listing.notes.last?.id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                }
                .onAppear {
                    guard let id = model.projection.highlightedNoteID else { return }
                    proxy.scrollTo(id, anchor: .bottom)
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
                    Text(model.voiceSettings.voiceMode.title)
                    Keycap(model.shortcuts.voiceCaptureCombo.displayString, size: 12)
                    Text(model.voiceSettings.voiceMode == .hold
                        ? "to speak, then release to save"
                        : "to start, then press again to save")
                }
                HStack(spacing: 5) {
                    Text("Or press")
                    Keycap(model.shortcuts.captureCombo.displayString, size: 12)
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

    @ViewBuilder
    private var footer: some View {
        if model.state.presentation == .cycling {
            HStack {
                Text("\(model.shortcuts.switchStackCombo.displayString) cycle · ⇧ reverse")
                Spacer()
                Text("Release modifiers to switch · esc cancel")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
        } else {
            browsingFooter
        }
    }

    private var browsingFooter: some View {
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
        switch model.state.focusedPane {
        case .stacks:
            let count = model.projection.facts.stacks.count
            return "\(count) stack\(count == 1 ? "" : "s") · ↑↓ preview · ⇥ notes"
        case .notes:
            let count = model.projection.shownStack?.notes.count ?? 0
            let name = model.projection.shownStack?.name ?? ""
            return "\(name) · \(noteCountLabel(count)) · ↑↓ select · ⇥ stacks"
        }
    }

    private func errorRow(_ error: StackStoreError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(noteStoreErrorMessage(error))
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
        let templates = model.projection.filteredTemplates
        return OverlayPanel(
            title: "Copy with template",
            emptyText: "No matching templates",
            isEmpty: templates.isEmpty,
            highlight: model.state.overlayHighlight,
            query: $model.overlayQuery,
            focus: $focus
        ) {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                let isHighlighted = index == model.state.overlayHighlight
                let isActive = template.id == model.settings.activeTemplateID
                OverlayRow(isHighlighted: isHighlighted, onHover: { model.send(.overlayHighlight(index)) }) {
                    model.send(.selectTemplate(template.id))
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 12)
                            .foregroundStyle(.primary)
                            .opacity(isActive ? 1 : 0)
                        Text(template.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if template.clearStackAfterExport {
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
enum PaletteTint {
    static let cornerRadius: CGFloat = 16
    static let railWidth: CGFloat = 3
    static let focusRailOpacity = 0.65
    static let dimmedRailOpacity = 0.45

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
    /// The other pane retains its selection without the keyboard focus marker.
    static let inactiveSelection = Color.primary.opacity(0.04)
    /// Pointer resting on a row.
    static let hover = Color.primary.opacity(0.04)
    /// Ring around the note being edited.
    static let editing = Color.primary.opacity(0.35)
    /// The rule beside a captured passage.
    static let quoteRule = Color.primary.opacity(0.22)

    static func wash(highlighted: Bool, dimmed: Bool = false, hovering: Bool = false) -> Color {
        guard highlighted else { return hovering ? hover : .clear }
        return dimmed ? inactiveSelection : selection
    }

    /// 3px leading rule that marks keyboard focus. Dimmed when the other pane
    /// owns the keys, still dark enough to read at a glance.
    struct FocusRail: View {
        var isDimmed = false

        var body: some View {
            Rectangle()
                .fill(Color.primary.opacity(isDimmed ? dimmedRailOpacity : focusRailOpacity))
                .frame(width: railWidth)
        }
    }
}

/// A palette row: flat and full-bleed, washed edge to edge when highlighted.
/// The unfocused pane keeps a quiet selection. A leading rule identifies
/// keyboard focus. One click highlights the row; a double click activates it.
private struct PaletteRow<Content: View>: View {
    let isHighlighted: Bool
    var isDimmed = false
    let onSelect: () -> Void
    let onActivate: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(PaletteTint.wash(highlighted: isHighlighted, dimmed: isDimmed, hovering: hovering))
            .overlay(alignment: .leading) {
                if isHighlighted {
                    PaletteTint.FocusRail(isDimmed: isDimmed)
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { onActivate() }
            .onTapGesture { onSelect() }
    }
}

/// One captured passage with its note. The note pane is always editable by
/// mouse; the highlight dims when the sidebar owns the keyboard.
private struct NoteCard: View {
    let entry: SendpointDomain.Note
    let isHighlighted: Bool
    var isDimmed = false
    let isEditing: Bool
    @Binding var draft: String
    var focus: FocusState<PaletteField?>.Binding
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var hovering = false

    private var quote: String {
        guard case let .selection(quote) = entry.subject else { return "" }
        return quote.nonblank ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the note being edited is a text field. Every other note is
            // plain text, so ↑↓ never re-measures a column of editors; ↩ or
            // a double click swaps the editor in.
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
            } else if let note = entry.body.nonblank {
                Text(note)
                    .font(.body)
                    .lineSpacing(2)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            } else {
                Text("Add a note…")
                    .font(.body)
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            if !quote.isEmpty {
                QuotedPassage(text: quote, isSubdued: isHighlighted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Notes sit on one continuous surface; the highlighted one simply
        // lifts to a soft grey.
        .background(PaletteTint.wash(highlighted: isHighlighted, dimmed: isDimmed, hovering: hovering))
        .overlay(alignment: .leading) {
            if isHighlighted {
                PaletteTint.FocusRail(isDimmed: isDimmed)
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(PaletteTint.editing, lineWidth: 1)
                .opacity(isEditing ? 1 : 0)
        )
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded { onEdit() }
                .exclusively(before: TapGesture().onEnded { onSelect() }),
            including: isEditing ? .subviews : .all
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }
}

/// A captured passage set as a quiet quotation: a thin rule down the left
/// and the text a step softer than the note it belongs to.
struct QuotedPassage: View {
    let text: String
    /// Soften the quote rule when a selection rail already marks the card.
    var isSubdued = false
    @State private var isExpanded = false
    @State private var heights = PassageHeights()

    private var isTruncated: Bool { heights.full > heights.preview + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            passage
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    passage.lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PassageHeightsKey.self,
                                value: PassageHeights(preview: proxy.size.height))
                        })
                        .hidden()
                }
                .background {
                    passage.lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PassageHeightsKey.self,
                                value: PassageHeights(full: proxy.size.height))
                        })
                        .hidden()
                }
                .padding(.leading, isSubdued ? 16 : 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(PaletteTint.quoteRule.opacity(isSubdued ? 0.5 : 1))
                        .frame(width: 2)
                }
            if isTruncated {
                Button(isExpanded ? "Collapse" : "Show passage") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, isSubdued ? 16 : 12)
                .accessibilityLabel(isExpanded ? "Collapse passage" : "Show full passage")
            }
        }
        .onPreferenceChange(PassageHeightsKey.self) { heights = $0 }
        .onChange(of: text) { isExpanded = false }
    }

    private var passage: some View {
        Text(text)
            .font(.callout)
            .lineSpacing(2)
            .foregroundStyle(.secondary)
    }
}

private struct PassageHeights: Equatable {
    var preview: CGFloat = 0
    var full: CGFloat = 0
}

private struct PassageHeightsKey: PreferenceKey {
    static let defaultValue = PassageHeights()
    static func reduce(value: inout PassageHeights, nextValue: () -> PassageHeights) {
        let next = nextValue()
        value.preview = max(value.preview, next.preview)
        value.full = max(value.full, next.full)
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
                    VStack(spacing: 0) {
                        rows()
                        if isEmpty {
                            Text(emptyText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                    .padding(.vertical, 4)
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
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(PaletteTint.wash(highlighted: isHighlighted))
        .overlay(alignment: .leading) {
            if isHighlighted {
                PaletteTint.FocusRail()
            }
        }
        .onHover { if $0 { onHover() } }
    }
}
