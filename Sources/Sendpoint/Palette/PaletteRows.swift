import SendpointDomain
import SwiftUI

struct RowShell<Content: View>: View {
    let isHighlighted: Bool
    var onHoverEnter: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, PaletteMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                Ink.Pill(radius: PaletteMetrics.pillRadius, fill: Ink.wash(highlighted: isHighlighted))
            }
            .contentShape(Rectangle())
            .onHover { if $0 { onHoverEnter?() } }
    }
}

struct NoteCard: View, Equatable {
    let entry: SendpointDomain.Note
    let isHighlighted: Bool
    let isEditing: Bool
    let today: Date
    @Binding var draft: String
    var focus: FocusState<PaletteField?>.Binding
    let onSelect: () -> Void
    let onEdit: () -> Void

    static func == (lhs: NoteCard, rhs: NoteCard) -> Bool {
        lhs.entry == rhs.entry
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isEditing == rhs.isEditing
            && lhs.today == rhs.today
            && lhs.draft == rhs.draft
    }

    @State private var hovering = false

    static let inset = PaletteMetrics.horizontalPadding

    private var quote: String {
        guard case let .selection(quote) = entry.subject else { return "" }
        return quote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var timeLabel: String { noteTimestampLabel(entry.createdAt, now: today) }

    var body: some View {
        if isEditing {
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
            Button(action: onSelect) {
                cardContent
            }
            .buttonStyle(.plain)
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
            Text(timeLabel)
                .font(.ui(11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityLabel("Captured \(timeLabel)")
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 14)
        .background {
            if isHighlighted {
                Ink.Pill(radius: PaletteMetrics.cardRadius, fill: Ink.wash(highlighted: true))
            } else if hovering {
                Ink.Pill(radius: PaletteMetrics.cardRadius, fill: Ink.hover)
            }
        }
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: PaletteMetrics.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                .padding(.horizontal, Ink.Pill.inset)
                .opacity(isEditing ? 1 : 0)
        )
    }

    private var noteColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
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

struct QuotedPassage: View {
    let text: String
    @State private var isExpanded = false
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        Group {
            if isTruncated || isExpanded {
                Button { isExpanded.toggle() } label: { measured.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse the passage" : "Show the whole passage")
                    .accessibilityHint(isExpanded ? "Collapses the passage" : "Shows the whole passage")
            } else {
                measured
            }
        }
        .onChange(of: text) { isExpanded = false }
    }

    private var measured: some View {
        passage
            .lineLimit(isExpanded ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                        if !isExpanded { clampedHeight = height }
                    }
                }
            }
            .background {
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
    }

    private var passage: some View {
        Text(text)
            .font(.ui(12.5))
            .lineSpacing(3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Previews

private struct NoteCardPreview: View {
    @FocusState private var focus: PaletteField?
    @State private var draft: String

    let entry: SendpointDomain.Note
    let isHighlighted: Bool
    let isEditing: Bool

    init(
        entry: SendpointDomain.Note,
        isHighlighted: Bool = false,
        isEditing: Bool = false
    ) {
        self.entry = entry
        self.isHighlighted = isHighlighted
        self.isEditing = isEditing
        _draft = State(initialValue: entry.body)
    }

    var body: some View {
        NoteCard(
            entry: entry,
            isHighlighted: isHighlighted,
            isEditing: isEditing,
            today: Calendar.current.startOfDay(for: Date()),
            draft: $draft,
            focus: $focus,
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
