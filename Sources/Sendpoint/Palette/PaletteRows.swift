import SendpointDomain
import SwiftUI

/// Shared row chrome for every concrete palette/overlay row.
///
/// One tiny helper so the split does not duplicate the pill logic across
/// the four concrete rows. It owns `@State hovering` itself (documented
/// here): palette rows read it as a hover wash, overlay rows track it but
/// never draw it — hover only reports outward so the reducer moves the
/// highlight, preserving the original "no hover wash" look exactly.
///
/// Pixel notes: both styles share padding, full-bleed frame, pill
/// background, contentShape-after-background, and hover handling in one
/// chain. The overlay's original order (contentShape inside the label,
/// background outside the Button) is unified to background-then-contentShape
/// inside the label; both cover the same full-bleed rect (the pill is inset
/// and never extends past the frame), so pixels and hit area are identical.
/// Palette style keeps the shared highlight pill (matchedGeometry) plus the
/// travel spring; overlay style keeps a plain highlight wash with no spring.
struct RowShell<Content: View>: View {
    enum Style: Equatable { case palette, overlay }

    let style: Style
    let isHighlighted: Bool
    var isDimmed = false
    var namespace: Namespace.ID? = nil
    /// Overlay rows forward hover-enter outward; palette rows pass nil.
    var onHoverEnter: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, PaletteMetrics.horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: style == .overlay ? 32 : nil,
                maxHeight: style == .palette ? .infinity : nil
            )
            // The pill is part of the hit area: the content shape is
            // declared after the background it must cover.
            .background {
                switch style {
                case .palette:
                    if isHighlighted {
                        if let namespace {
                            Ink.Pill(radius: PaletteMetrics.pillRadius, fill: Ink.wash(highlighted: true, dimmed: isDimmed))
                                .matchedGeometryEffect(id: "highlight", in: namespace)
                        } else {
                            Ink.Pill(radius: PaletteMetrics.pillRadius, fill: Ink.wash(highlighted: true, dimmed: isDimmed))
                        }
                    } else if hovering {
                        Ink.Pill(radius: PaletteMetrics.pillRadius, fill: Ink.hover)
                    }
                case .overlay:
                    // Always present, as before (clear when idle): no dim,
                    // no hover wash, no shared-geometry slide.
                    Ink.Pill(radius: PaletteMetrics.pillRadius, fill: Ink.wash(highlighted: isHighlighted))
                }
            }
            .contentShape(Rectangle())
            // Scoped to this row: only the rows whose highlight flips get the
            // spring, so the pill still slides while coincident changes in
            // other rows no longer animate. Overlay rows pass nil: no spring,
            // exactly as before.
            .animation(style == .palette ? StackPaletteView.travel : nil, value: isHighlighted)
            .onHover {
                hovering = $0
                if $0 { onHoverEnter?() }
            }
    }
}

/// A stack sidebar row: flat and full-bleed, washed edge to edge when
/// highlighted. The unfocused pane keeps a quiet selection. One click
/// highlights the row; a double click activates it. While renaming, the row
/// hosts the rename editor as a plain container: a Button around a focused
/// TextField would swallow the clicks that focus and drive it.
struct PaletteStackRow: View, Equatable {
    let stack: StackItemFacts
    let position: Int
    let showsDigit: Bool
    let isHighlighted: Bool
    var isDimmed = false
    var isRenaming = false
    /// Rendered rename text per keystroke (from the inline-edit binding).
    /// Empty while not renaming so unrelated edits never dirty this row.
    var renameText = ""
    var focus: FocusState<PaletteField?>.Binding
    var stackNamespace: Namespace.ID
    var dotNamespace: Namespace.ID
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onEditText: (String) -> Void

    /// Rendered inputs only. Closures, the shared highlight/dot namespaces,
    /// and the focus binding are identities, not pixels; the rename string
    /// value stands in for its binding. When in doubt this returns false.
    static func == (lhs: PaletteStackRow, rhs: PaletteStackRow) -> Bool {
        lhs.stack == rhs.stack
            && lhs.position == rhs.position
            && lhs.showsDigit == rhs.showsDigit
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isDimmed == rhs.isDimmed
            && lhs.isRenaming == rhs.isRenaming
            && lhs.renameText == rhs.renameText
    }

    var body: some View {
        // VoiceOver name for the double-click gesture. The single-click
        // select stays the Button's native activate action, so a VoiceOver
        // user gets both: double-tap selects, custom action activates.
        let activateLabel = "Switch to \(stack.name)"
        if isRenaming {
            // No single-tap handler: the delayed select it used to send was
            // always dropped by the reducer's inlineEdit guard, and the
            // double-tap commit path below stays exactly as it was.
            RowShell(style: .palette, isHighlighted: isHighlighted, isDimmed: isDimmed, namespace: stackNamespace) {
                StackRow(
                    noteCount: stack.noteCount,
                    position: position,
                    showsDigit: false
                ) {
                    TextField(
                        "Stack name",
                        text: Binding(
                            get: { renameText },
                            set: { onEditText($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.ui(13.5, weight: .medium))
                    .focused(focus, equals: .rename(stack.id))
                    .padding(.leading, StackRowName.gutter)
                }
            }
            .accessibilityAction(named: Text(activateLabel)) { onActivate() }
            .focusable()
            .onTapGesture(count: 2) { onActivate() }
        } else {
            // A Button fires per click without waiting out the double-tap
            // window, so a single click highlights immediately. A double
            // click then yields select, select, activate; re-selecting the
            // same row is idempotent, so the extra select is harmless.
            Button(action: onSelect) {
                RowShell(style: .palette, isHighlighted: isHighlighted, isDimmed: isDimmed, namespace: stackNamespace) {
                    StackRow(
                        name: stack.name,
                        noteCount: stack.noteCount,
                        isCurrent: stack.isCurrent,
                        position: position,
                        showsDigit: showsDigit,
                        dotNamespace: dotNamespace
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityAction(named: Text(activateLabel)) { onActivate() }
            .focusable()
            .onTapGesture(count: 2) { onActivate() }
        }
    }
}

/// The offer to create a stack named after the query: same pill chrome as
/// the stack rows, never an editor.
struct PaletteCreateRow: View, Equatable {
    let name: String
    let isHighlighted: Bool
    var isDimmed = false
    var namespace: Namespace.ID
    let onSelect: () -> Void
    let onActivate: () -> Void

    /// Rendered inputs only: the create name (per keystroke), highlight,
    /// and dim. The namespace and closures are identities. When in doubt
    /// this returns false.
    static func == (lhs: PaletteCreateRow, rhs: PaletteCreateRow) -> Bool {
        lhs.name == rhs.name
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isDimmed == rhs.isDimmed
    }

    var body: some View {
        Button(action: onSelect) {
            RowShell(style: .palette, isHighlighted: isHighlighted, isDimmed: isDimmed, namespace: namespace) {
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
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: Text("Create stack “\(name)”")) { onActivate() }
        .focusable()
        .onTapGesture(count: 2) { onActivate() }
    }
}

/// One captured passage with its note. The note pane is always editable by
/// mouse; the highlight dims when the sidebar owns the keyboard.
struct NoteCard: View, Equatable {
    let entry: SendpointDomain.Note
    let isHighlighted: Bool
    var isDimmed = false
    let isEditing: Bool
    @Binding var draft: String
    var focus: FocusState<PaletteField?>.Binding
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onEdit: () -> Void

    /// Rendered inputs only. The focus binding, the shared highlight
    /// namespace, and the action closures are identities, not pixels; the
    /// draft's current string stands in for the draft binding. When in
    /// doubt this returns false: a stale note is worse than a re-render.
    static func == (lhs: NoteCard, rhs: NoteCard) -> Bool {
        lhs.entry == rhs.entry
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isDimmed == rhs.isDimmed
            && lhs.isEditing == rhs.isEditing
            && lhs.draft == rhs.draft
    }

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

    /// "3:42 PM" reads bare to VoiceOver; the card already groups by day, so
    /// the label only needs to say what the time is.
    private var timeLabel: String { "Captured at \(noteTimeLabel(entry.createdAt))" }

    var body: some View {
        if isEditing {
            // The focused TextField stays a plain container with today's
            // gestures untouched: a Button around it would swallow the
            // clicks that focus and drive it.
            cardContent
                .focusable()
                .gesture(
                    TapGesture(count: 2).onEnded { onEdit() }
                        .exclusively(before: TapGesture().onEnded { onSelect() }),
                    including: .subviews
                )
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            // A Button fires per click without waiting out the double-tap
            // window, so a single click highlights immediately. A double
            // click then yields select, select, edit; re-selecting the same
            // note is idempotent, so the extra select is harmless.
            Button(action: onSelect) {
                cardContent
            }
            .buttonStyle(.plain)
            // The Button's native activate is select; the double-click edit
            // has no VoiceOver equivalent, so it is a custom action.
            .accessibilityHint("Double-click to edit.")
            .accessibilityAction(named: Text("Edit note")) { onEdit() }
            .focusable()
            .onTapGesture(count: 2) { onEdit() }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 16) {
            noteColumn
            Text(noteTimeLabel(entry.createdAt))
                .font(.mono(10.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .accessibilityLabel(timeLabel)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 14)
        // Notes sit on one continuous surface; the highlighted one lifts on
        // a rounded pill, deeper when the keyboard is here. The pill is one
        // shape shared by the list, so it slides between notes.
        .background {
            if isHighlighted {
                Ink.Pill(radius: PaletteMetrics.cardRadius, fill: Ink.wash(highlighted: true, dimmed: isDimmed))
                    .matchedGeometryEffect(id: "highlight", in: namespace)
            } else if hovering {
                Ink.Pill(radius: PaletteMetrics.cardRadius, fill: Ink.hover)
            }
        }
        // The pill is part of the hit area: the content shape is declared
        // after the background it must cover (and before the editing-ring
        // overlay, which sits inset inside this rectangle either way).
        .contentShape(Rectangle())
        // Scoped to this card (see RowShell): the pill still slides on
        // highlight moves; other notes' changes in the same transaction don't
        // spring. Placed before the editing-ring overlay so that ring never
        // rides this spring.
        .animation(StackPaletteView.travel, value: isHighlighted)
        .overlay(
            RoundedRectangle(cornerRadius: PaletteMetrics.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                .padding(.horizontal, Ink.Pill.inset)
                .opacity(isEditing ? 1 : 0)
        )
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
                    .accessibilityLabel("Empty note")
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
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            passage
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // Visible height, observed in place: no extra text layout.
                    // Latched while collapsed so expanding keeps the Collapse button.
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                            if !isExpanded { clampedHeight = height }
                        }
                    }
                }
                .background {
                    // The single hidden measure: full text at the same width.
                    passage.lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                                    fullHeight = height
                                }
                            }
                        }
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
        .onChange(of: text) { isExpanded = false }
    }

    private var passage: some View {
        Text(text)
            .font(.mono(12))
            .lineSpacing(4)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Previews

private struct NoteCardPreview: View {
    @Namespace private var namespace
    @FocusState private var focus: PaletteField?
    @State private var draft: String

    let entry: SendpointDomain.Note
    let isHighlighted: Bool
    let isDimmed: Bool
    let isEditing: Bool

    init(
        entry: SendpointDomain.Note,
        isHighlighted: Bool = false,
        isDimmed: Bool = false,
        isEditing: Bool = false
    ) {
        self.entry = entry
        self.isHighlighted = isHighlighted
        self.isDimmed = isDimmed
        self.isEditing = isEditing
        _draft = State(initialValue: entry.body)
    }

    var body: some View {
        NoteCard(
            entry: entry,
            isHighlighted: isHighlighted,
            isDimmed: isDimmed,
            isEditing: isEditing,
            draft: $draft,
            focus: $focus,
            namespace: namespace,
            onSelect: {},
            onEdit: {}
        )
        .frame(width: 420)
    }
}

#Preview("NoteCard plain") {
    NoteCardPreview(entry: .sampleStandalone)
        .padding()
}

#Preview("NoteCard highlighted") {
    NoteCardPreview(entry: .sample, isHighlighted: true)
        .padding()
}

#Preview("NoteCard editing") {
    NoteCardPreview(entry: .sample, isHighlighted: true, isEditing: true)
        .padding()
}

#Preview("QuotedPassage short") {
    QuotedPassage(text: PreviewCopy.shortPassage)
        .frame(width: 320)
        .padding()
}

#Preview("QuotedPassage long") {
    QuotedPassage(text: PreviewCopy.longPassage)
        .frame(width: 320)
        .padding()
}
