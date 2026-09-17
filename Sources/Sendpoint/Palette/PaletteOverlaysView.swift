import Foundation
import SendpointDomain
import SwiftUI

/// The floating ⌘K / ⌘P menus in the palette's corner: a dim tap-to-close
/// layer with the grouped action or template rows and a filter field below
/// them. Takes the shell-threaded projection plus small scalars.
struct PaletteOverlaysView: View {
    let projection: PaletteProjection
    let overlay: PaletteOverlay?
    let highlight: Int
    @Binding var overlayQuery: String
    let activeTemplateID: UUID
    let focus: FocusState<PaletteField?>.Binding
    let onEvent: (PaletteEvent) -> Void

    var body: some View {
        if let overlay {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { onEvent(.closeOverlay) }
                Group {
                    switch overlay {
                    case .actions: actionsMenu(items: projection.filteredActionItems)
                    case .templates: templatesMenu(
                        templates: projection.filteredTemplates,
                        activeTemplateID: activeTemplateID
                    )
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 48)
            }
            .transition(.opacity)
        }
    }

    private func actionsMenu(items: [PaletteActionItem]) -> some View {
        OverlayPanel(
            placeholder: "Search actions",
            emptyText: "Nothing more to do here",
            isEmpty: items.isEmpty,
            highlight: highlight,
            query: $overlayQuery,
            focus: focus
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index == 0 || items[index - 1].section != item.section {
                    OverlaySectionLabel(section: item.section)
                }
                let isHighlighted = index == highlight
                PaletteActionRow(
                    item: item,
                    isHighlighted: isHighlighted,
                    onHover: { onEvent(.overlayHighlight(index)) },
                    onPerform: { onEvent(.perform(item.action)) }
                )
                .equatable()
                .id(index)
            }
        }
    }

    private func templatesMenu(templates: [Template], activeTemplateID: UUID) -> some View {
        OverlayPanel(
            placeholder: "Search templates",
            emptyText: "No matching templates",
            isEmpty: templates.isEmpty,
            highlight: highlight,
            query: $overlayQuery,
            focus: focus
        ) {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                let isHighlighted = index == highlight
                let isActive = template.id == activeTemplateID
                PaletteTemplateRow(
                    template: template,
                    isHighlighted: isHighlighted,
                    isActive: isActive,
                    onHover: { onEvent(.overlayHighlight(index)) },
                    onSelect: { onEvent(.selectTemplate(template.id)) }
                )
                .equatable()
                .id(index)
            }
        }
    }
}

struct OverlaySectionLabel: View {
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
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// The floating menu in the corner: grouped rows and a filter field below
/// them, the way Raycast lays out its action panel.
struct OverlayPanel<Rows: View>: View {
    let placeholder: String
    let emptyText: String
    let isEmpty: Bool
    /// Index of the highlighted row; the list scrolls to keep it in view.
    let highlight: Int
    @Binding var query: String
    var focus: FocusState<PaletteField?>.Binding
    @ViewBuilder let rows: () -> Rows

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
                // Tab reaches these rows today (the overlay lets Tab fall
                // through to the views), so they form one focus section with
                // the filter field below. No key handling lives here: arrows
                // and ↩ still go through the palette's global key monitor.
                .focusSection()
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
            .frame(height: PaletteMetrics.barHeight)
        }
        .frame(width: PaletteMetrics.overlayWidth)
        .modifier(OverlaySurface())
    }
}

/// The floating menu surface for the overlay menus: one rounded fill, one
/// rim, one shadow. Lives here with its only caller.
private struct OverlaySurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PaletteMetrics.overlayRadius, style: .continuous)
                    .fill(Ink.raised(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaletteMetrics.overlayRadius, style: .continuous)
                    .strokeBorder(Ink.rim(scheme), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 24, y: 10)
    }
}

/// One ⌘K action row: title plus keys, red when destructive. The Button's
/// native activate already performs the row, so VoiceOver needs nothing
/// extra. Hover only reports outward so the reducer moves the highlight;
/// there is deliberately no hover wash, exactly as before.
struct PaletteActionRow: View, Equatable {
    let item: PaletteActionItem
    let isHighlighted: Bool
    let onHover: () -> Void
    let onPerform: () -> Void
    @Environment(\.colorScheme) private var scheme

    /// Rendered inputs only: the whole action item (title, keys,
    /// destructiveness, section) plus highlight. Closures are identities and
    /// the color scheme arrives via the environment. When in doubt false.
    static func == (lhs: PaletteActionRow, rhs: PaletteActionRow) -> Bool {
        lhs.item == rhs.item && lhs.isHighlighted == rhs.isHighlighted
    }

    var body: some View {
        Button(action: onPerform) {
            RowShell(style: .overlay, isHighlighted: isHighlighted, onHoverEnter: onHover) {
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
        }
        .buttonStyle(.plain)
        // No custom action: the Button's native activate already performs the
        // row, so VoiceOver users need nothing extra here.
        .focusable()
    }
}

/// One ⌘P template row: active dot, name, and the "clears after copy" note.
/// Same Button/no-custom-action contract as the action row.
struct PaletteTemplateRow: View, Equatable {
    let template: Template
    let isHighlighted: Bool
    let isActive: Bool
    let onHover: () -> Void
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    /// Rendered inputs only: the whole template (name plus the clears-after
    /// flag), highlight, and the active dot. Closures are identities and the
    /// color scheme arrives via the environment. When in doubt false.
    static func == (lhs: PaletteTemplateRow, rhs: PaletteTemplateRow) -> Bool {
        lhs.template == rhs.template
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Button(action: onSelect) {
            RowShell(style: .overlay, isHighlighted: isHighlighted, onHoverEnter: onHover) {
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
        }
        .buttonStyle(.plain)
        .focusable()
    }
}

// MARK: - Previews

private struct OverlayPanelPreview: View {
    @FocusState private var focus: PaletteField?
    @State private var query = ""

    private static let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    var body: some View {
        OverlayPanel(
            placeholder: "Search actions",
            emptyText: "Nothing more to do here",
            isEmpty: false,
            highlight: 1,
            query: $query,
            focus: $focus
        ) {
            PaletteActionRow(
                item: PaletteActionItem(action: .editNote(Self.noteID), title: "Edit", keys: "↩", section: .note),
                isHighlighted: false,
                onHover: {},
                onPerform: {}
            )
            PaletteActionRow(
                item: PaletteActionItem(action: .copyNote(Self.noteID), title: "Copy", keys: "⌘C", section: .note),
                isHighlighted: true,
                onHover: {},
                onPerform: {}
            )
            PaletteActionRow(
                item: PaletteActionItem(action: .deleteNote(Self.noteID), title: "Delete", keys: "⌘⌫", section: .note),
                isHighlighted: false,
                onHover: {},
                onPerform: {}
            )
        }
        .padding()
    }
}

#Preview("OverlayPanel") {
    OverlayPanelPreview()
}

#Preview("PaletteActionRow") {
    VStack(spacing: 0) {
        PaletteActionRow(
            item: PaletteActionItem(
                action: .copyNote(UUID(uuidString: "00000000-0000-0000-0000-000000000102")!),
                title: "Highlighted row",
                keys: "⌘C",
                section: .note
            ),
            isHighlighted: true,
            onHover: {},
            onPerform: {}
        )
        PaletteActionRow(
            item: PaletteActionItem(
                action: .editNote(UUID(uuidString: "00000000-0000-0000-0000-000000000102")!),
                title: "Plain row",
                keys: "↩",
                section: .note
            ),
            isHighlighted: false,
            onHover: {},
            onPerform: {}
        )
    }
    .frame(width: 320)
    .padding()
}

#Preview("PaletteTemplateRow") {
    VStack(spacing: 0) {
        PaletteTemplateRow(
            template: Template(
                name: "Meeting",
                preamble: "",
                includeTimestamps: true,
                includeHeading: true,
                includeNoteNumbers: false,
                clearStackAfterExport: true
            ),
            isHighlighted: true,
            isActive: true,
            onHover: {},
            onSelect: {}
        )
        PaletteTemplateRow(
            template: Template.sample,
            isHighlighted: false,
            isActive: false,
            onHover: {},
            onSelect: {}
        )
    }
    .frame(width: 320)
    .padding()
}
