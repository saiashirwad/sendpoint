import AppKit
import SendpointDomain
import SwiftUI

/// The one surface for stacks: a stack sidebar beside the highlighted
/// stack's notes. Tab and the arrows move the keyboard between the panes;
/// both are always drawn, and the unfocused one dims its highlight.
struct StackPaletteView: View {
    @Bindable var model: StackPaletteModel
    @FocusState private var focus: PaletteField?
    @Environment(\.colorScheme) private var scheme

    static let minimumSize = CGSize(width: 780, height: 460)
    private let rowHeight: CGFloat = 36
    /// Where each note sits in the list's viewport. A plain class, so the
    /// frames can update on every scroll without redrawing the palette.
    @State private var noteFrames = NoteFrames()
    private static let notesSpace = "notes"
    /// One highlight pill per pane and one current-stack dot, each a single
    /// shape that slides between rows instead of popping.
    @Namespace private var noteHighlight
    @Namespace private var stackHighlight
    @Namespace private var currentDot

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.state.presentation != .cycling, let undo = model.projection.facts.undo {
                Hairline()
                undoBanner(undo)
            }
            if let message = model.state.problem {
                Hairline()
                problemRow(message)
            } else if let error = model.store.error {
                Hairline()
                errorRow(error)
            }
            Hairline()
            footer
        }
        .frame(
            minWidth: Self.minimumSize.width, maxWidth: .infinity,
            minHeight: Self.minimumSize.height, maxHeight: .infinity
        )
        .background(Backdrop())
        .font(.uiBody)
        .overlay { overlayMenu }
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

    // MARK: - Header

    /// "3 OF 12" while a search narrows the focused pane.
    private var matchReadout: String? {
        guard model.query.nonblank != nil, model.state.presentation != .cycling else { return nil }
        let (matches, total): (Int, Int) = switch model.state.focusedPane {
        case .stacks: (model.projection.stackListing.stacks.count, model.projection.facts.stacks.count)
        case .notes: (model.projection.noteListing.notes.count, model.projection.shownStack?.notes.count ?? 0)
        }
        return "\(matches) OF \(total)"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            if model.state.presentation == .cycling {
                Text("Switch stack")
                    .font(.ui(15, weight: .medium))
                Spacer()
            } else {
                TextField(model.projection.searchPlaceholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.ui(15))
                    .focused($focus, equals: .search)
                    .disabled(model.state.inlineEdit != nil || model.state.overlay != nil)
            }

            if let matches = matchReadout {
                Text(matches)
                    .font(.mono(10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: matches)
                    .accessibilityLabel(matches.lowercased())
            }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    // MARK: - Content

    private var content: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                stackColumn
                    .frame(width: sidebarWidth(for: proxy.size.width))
                Hairline(axis: .vertical)
                notePane
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
                            Text("Nothing called “\(model.query.trimmingCharacters(in: .whitespaces))”.")
                                .font(.uiCallout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                        }
                    }
                    .animation(Self.travel, value: model.state.stackState.highlight)
                    .animation(Self.travel, value: model.projection.facts.currentStackID)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.state.stackState.highlight) {
                    guard let highlight = model.state.stackState.highlight else { return }
                    proxy.scrollTo(highlight, anchor: nil)
                }
            }
            Hairline()
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
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("New stack")
                        .font(.ui(13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("⌘N")
                        .font(.mono(10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Create a stack (⌘N)")
        }
    }

    private func undoBanner(_ undo: StackUndoFacts) -> some View {
        HStack(spacing: 12) {
            Text(undo.notification)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(undo.notification)
            QuietButton("Undo", keys: "⌘Z") {
                model.send(.perform(.undoClear))
            }
            .help("Put the cleared notes back")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
    }

    private func stackRow(_ stack: StackItemFacts, position: Int) -> some View {
        let isHighlighted = model.state.stackState.highlight == .stack(stack.id)
        var isRenaming = false
        if case let .renameStack(id, _, _) = model.state.inlineEdit, id == stack.id { isRenaming = true }
        let showsDigit = model.state.focusedPane == .stacks && model.state.presentation != .cycling
        return PaletteRow(
            isHighlighted: isHighlighted,
            isDimmed: model.state.focusedPane != .stacks,
            namespace: stackHighlight,
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
                        .padding(.leading, StackRowName.gutter)
                }
            } else {
                StackRow(
                    name: stack.name,
                    noteCount: stack.noteCount,
                    isCurrent: stack.isCurrent,
                    position: position,
                    showsDigit: showsDigit,
                    dotNamespace: currentDot
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
            namespace: stackHighlight,
            onSelect: { model.send(.chooseCreate(name)) },
            onActivate: { model.send(.perform(.createStack(name))) }
        ) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                (Text("Create ") + Text("“\(name)”").fontWeight(.semibold))
                    .font(.ui(13.5))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(isHighlighted ? "↩" : "⌘↩")
                    .font(.mono(10.5))
                    .foregroundStyle(.quaternary)
            }
        }
        .foregroundStyle(Color.primary)
        .frame(height: rowHeight)
    }

    private var inlineCreateRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            inlineNameField(field: .create, placeholder: "New stack name")
            Spacer(minLength: 8)
            Keycap("↩", size: 10)
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(Rectangle().fill(Ink.selection))
    }

    /// The name being typed. A problem with it is reported once, in the
    /// problem row under the panes, where it has room and its buttons.
    private func inlineNameField(field: PaletteField, placeholder: String) -> some View {
        TextField(
            placeholder,
            text: Binding(
                get: { (model.state.inlineEdit?.text ?? "") },
                set: { model.send(.editText($0)) }
            )
        )
        .textFieldStyle(.plain)
        .font(.ui(13.5, weight: .medium))
        .focused($focus, equals: field)
    }

    // MARK: - Notes

    @ViewBuilder
    private var notePane: some View {
        if case let .create(name) = model.state.stackState.highlight {
            placeholder(title: "Create “\(name)”", detail: "Press ↩ to make it and switch to it.")
        } else if let stack = model.projection.shownStack {
            noteCards(stack: stack)
        } else {
            placeholder(title: "No stack selected", detail: nil)
        }
    }

    @ViewBuilder
    private func noteCards(stack: Stack) -> some View {
        let listing = model.projection.noteListing
        let wasCleared = model.projection.facts.undo?.stackID == stack.id
        if stack.notes.isEmpty && wasCleared, let undo = model.projection.facts.undo {
            VStack(spacing: 18) {
                placeholder(title: "Stack cleared", detail: "\(noteCountLabel(undo.noteCount)) set aside.")
                    .frame(maxHeight: 120)
                QuietButton("Undo", keys: "⌘Z") {
                    model.send(.perform(.undoClear))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stack.notes.isEmpty {
            emptyState
        } else if listing.isEmpty {
            placeholder(
                title: "No notes match “\(model.query.trimmingCharacters(in: .whitespaces))”",
                detail: nil
            )
        } else {
            ScrollView {
                    // A plain stack: stacks hold a handful of notes, and
                    // lazy stacks of variable-height text re-measure on
                    // every move.
                    VStack(spacing: 0) {
                        ForEach(noteDaySections(listing.notes), id: \.label) { section in
                            NoteDayLabel(section.label)
                            ForEach(Array(section.notes.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    Hairline().padding(.horizontal, NoteCard.inset)
                                }
                                noteCard(entry)
                            }
                        }
                    }
                    .animation(Self.travel, value: model.projection.highlightedNoteID)
                    .padding(.vertical, 6)
                    .background(ScrollProbe(handle: noteFrames.scroll))
            }
            .coordinateSpace(name: Self.notesSpace)
            .onPreferenceChange(NoteFramesKey.self) { frames in
                noteFrames.frames.merge(frames) { $1 }
                // A landing stays armed until a fresh frame shows the note
                // at the bottom edge: text lays out over a few passes, and
                // a frame measured early is shorter than the note ends up.
                noteFrames.settle()
            }
            .onChange(of: model.projection.highlightedNoteID) {
                // Keyboard movement brings the highlighted note into view,
                // and only when it is cut off, so the list never jumps
                // under a note already on screen.
                guard model.state.focusedPane == .notes,
                      let id = model.projection.highlightedNoteID else { return }
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
                guard let id = model.projection.highlightedNoteID ?? listing.notes.last?.id else { return }
                noteFrames.land(on: id)
            }
        }
    }

    private func noteCard(_ entry: SendpointDomain.Note) -> some View {
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
            namespace: noteHighlight,
            onSelect: { model.send(.chooseNote(entry.id)) },
            onEdit: { model.send(.perform(.editNote(entry.id))) }
        )
        .id(entry.id)
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: NoteFramesKey.self,
                value: [entry.id: geometry.frame(in: .named(Self.notesSpace))]
            )
        })
    }

    /// How a highlight pill or the current-stack dot slides to its new row.
    private static let travel = Animation.spring(response: 0.18, dampingFraction: 0.92)

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

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if model.state.presentation == .cycling {
            HStack(spacing: 14) {
                hint(model.shortcuts.switchStackCombo.displayString, "cycle")
                hint("⇧", "reverse")
                Spacer()
                Text("Release to switch")
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
        } else {
            browsingFooter
        }
    }

    private var browsingFooter: some View {
        HStack(spacing: 16) {
            if let flash = model.state.flash {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.accent(scheme))
                    Text(flash.text)
                        .font(.ui(12, weight: .medium))
                }
                .transition(.opacity)
            } else {
                context
            }

            Spacer()

            Button {
                model.send(.toggleOverlay(.templates))
            } label: {
                HStack(spacing: 7) {
                    Text("Template")
                        .font(.ui(12.5))
                        .foregroundStyle(.tertiary)
                    Text(model.projection.activeTemplate.name)
                        .font(.ui(12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 2)
                    Keycap("⌘P", size: 10.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Template used when copying (⌘P)")

            if let primary = model.projection.primaryAction {
                QuietButton(primary.verb, keys: "↩") {
                    model.send(.perform(primary.action))
                }
            }

            QuietButton("Actions", keys: "⌘K") {
                model.send(.toggleOverlay(.actions))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.state.flash?.generation)
        .padding(.horizontal, 18)
        .frame(height: 40)
    }

    /// Where the keyboard is and how to move it.
    private var context: some View {
        HStack(spacing: 12) {
            switch model.state.focusedPane {
            case .stacks:
                let count = model.projection.facts.stacks.count
                Text("\(count) stack\(count == 1 ? "" : "s")")
                hint("⇥", "notes")
            case .notes:
                let count = model.projection.shownStack?.notes.count ?? 0
                Text("\(model.projection.shownStack?.name ?? "") · \(noteCountLabel(count))")
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.3), value: count)
                hint("⇥", "stacks")
            }
        }
        .font(.uiCaption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(keys, size: 10, isMuted: true)
            Text(label)
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
        }
    }

    private func problemRow(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.uiCaption)
                .foregroundStyle(Ink.amber(scheme))
                .lineLimit(2)
            Spacer()
            if case .failed(_, _, true) = model.state.interaction {
                QuietButton("Retry") { model.send(.retry) }
            } else if case .failed = model.state.interaction {
                QuietButton("Dismiss") { model.send(.cancelEdit) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func errorRow(_ error: StackStoreError) -> some View {
        HStack(spacing: 12) {
            Text(noteStoreErrorMessage(error))
                .font(.uiCaption)
                .foregroundStyle(Ink.amber(scheme))
                .lineLimit(2)
            Spacer()
            if model.store.hasPendingMutations {
                QuietButton("Retry") { model.send(.retry) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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
                .padding(.bottom, 48)
            }
            .transition(.opacity)
        }
    }

    private var actionsMenu: some View {
        let items = model.projection.filteredActionItems
        return OverlayPanel(
            placeholder: "Search actions",
            emptyText: "Nothing more to do here",
            isEmpty: items.isEmpty,
            highlight: model.state.overlayHighlight,
            query: $model.overlayQuery,
            focus: $focus
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index == 0 || items[index - 1].section != item.section {
                    OverlaySectionLabel(section: item.section)
                }
                let isHighlighted = index == model.state.overlayHighlight
                OverlayRow(isHighlighted: isHighlighted, onHover: { model.send(.overlayHighlight(index)) }) {
                    model.send(.perform(item.action))
                } content: {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.ui(13, weight: .medium))
                            .foregroundStyle(item.isDestructive ? Ink.accent(scheme) : Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.keys)
                            .font(.mono(10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .id(index)
            }
        }
    }

    private var templatesMenu: some View {
        let templates = model.projection.filteredTemplates
        return OverlayPanel(
            placeholder: "Search templates",
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
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Ink.accent(scheme))
                            .frame(width: 5, height: 5)
                            .opacity(isActive ? 1 : 0)
                        Text(template.name)
                            .font(.ui(13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if template.clearStackAfterExport {
                            Text("clears after copy")
                                .font(.ui(10.5))
                                .foregroundStyle(.tertiary)
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

/// A palette row: flat and full-bleed, washed edge to edge when highlighted.
/// The unfocused pane keeps a quiet selection. A leading rule identifies
/// keyboard focus. One click highlights the row; a double click activates it.
private struct PaletteRow<Content: View>: View {
    let isHighlighted: Bool
    var isDimmed = false
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onActivate: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background {
                if isHighlighted {
                    Ink.Pill(radius: 7, fill: Ink.wash(highlighted: true, dimmed: isDimmed))
                        .matchedGeometryEffect(id: "highlight", in: namespace)
                } else if hovering {
                    Ink.Pill(radius: 7, fill: Ink.hover)
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
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var hovering = false

    /// Text edge from the pane's edge, so a highlighted note has room
    /// inside its pill and the hairlines line up with the text.
    static let inset: CGFloat = 22

    /// The passage without the blank lines a selection often drags along,
    /// so the rule beside it ends where the words do.
    private var quote: String {
        guard case let .selection(quote) = entry.subject else { return "" }
        return quote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            noteColumn
            Text(noteTimeLabel(entry.createdAt))
                .font(.mono(10.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 14)
        // Notes sit on one continuous surface; the highlighted one lifts on
        // a rounded pill, deeper when the keyboard is here. The pill is one
        // shape shared by the list, so it slides between notes.
        .background {
            if isHighlighted {
                Ink.Pill(radius: 10, fill: Ink.wash(highlighted: true, dimmed: isDimmed))
                    .matchedGeometryEffect(id: "highlight", in: namespace)
            } else if hovering {
                Ink.Pill(radius: 10, fill: Ink.hover)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                .padding(.horizontal, Ink.Pill.inset)
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
    }

    private var noteColumn: some View {
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
                .font(.ui(13.5))
                .lineSpacing(3)
                .lineLimit(1...8)
                .focused(focus, equals: .note(entry.id))
            } else if let note = entry.body.nonblank {
                Text(note)
                    .font(.ui(13.5))
                    .lineSpacing(3)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            } else {
                Text("Add a note…")
                    .font(.ui(13.5))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            if !quote.isEmpty {
                QuotedPassage(text: quote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A captured passage, set in mono like a transcript: it is a record of
/// someone else's words, and it reads that way.
struct QuotedPassage: View {
    let text: String
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
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 1.5)
                }
            if isTruncated {
                Button(isExpanded ? "Collapse" : "Show passage") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
                .accessibilityLabel(isExpanded ? "Collapse passage" : "Show full passage")
            }
        }
        .onPreferenceChange(PassageHeightsKey.self) { heights = $0 }
        .onChange(of: text) { isExpanded = false }
    }

    private var passage: some View {
        Text(text)
            .font(.mono(12))
            .lineSpacing(4)
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

/// A section heading inside the ⌘K menu: what the rows below act on.
/// The day a run of notes was captured, in the settings' micro-label voice.
private struct NoteDayLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        SettingsLabel(title)
            .padding(.horizontal, NoteCard.inset)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverlaySectionLabel: View {
    let section: PaletteActionSection

    var body: some View {
        HStack(spacing: 8) {
            SettingsLabel(section.label)
            Spacer(minLength: 8)
            if let detail = section.detail {
                Text(detail)
                    .font(.ui(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// The floating menu in the corner: grouped rows and a filter field below
/// them, the way Raycast lays out its action panel.
private struct OverlayPanel<Rows: View>: View {
    let placeholder: String
    let emptyText: String
    let isEmpty: Bool
    /// Index of the highlighted row; the list scrolls to keep it in view.
    let highlight: Int
    @Binding var query: String
    var focus: FocusState<PaletteField?>.Binding
    @ViewBuilder let rows: () -> Rows
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        rows()
                        if isEmpty {
                            Text(emptyText)
                                .font(.uiCallout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlight) { proxy.scrollTo(highlight) }
            }
            Hairline()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.ui(13))
                    .focused(focus, equals: .overlay)
                Keycap("esc", size: 10, isMuted: true)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Ink.raised(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Ink.rim(scheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 24, y: 10)
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
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Ink.Pill(radius: 7, fill: Ink.wash(highlighted: isHighlighted)))
        .onHover { if $0 { onHover() } }
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

private struct NoteFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
