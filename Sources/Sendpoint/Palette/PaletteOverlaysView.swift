import Foundation
import SendpointDomain
import SwiftUI

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
        SettingsLabel(section.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaletteMetrics.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

struct OverlayPanel<Rows: View>: View {
    let placeholder: String
    let emptyText: String
    let isEmpty: Bool
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
                    .padding(.vertical, 6)
                }
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

struct PaletteActionRow: View, Equatable {
    let item: PaletteActionItem
    let isHighlighted: Bool
    let onHover: () -> Void
    let onPerform: () -> Void
    @Environment(\.colorScheme) private var scheme

    static func == (lhs: PaletteActionRow, rhs: PaletteActionRow) -> Bool {
        lhs.item == rhs.item && lhs.isHighlighted == rhs.isHighlighted
    }

    var body: some View {
        Button(action: onPerform) {
            RowShell(isHighlighted: isHighlighted, onHoverEnter: onHover) {
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
        .focusable()
    }
}

struct PaletteTemplateRow: View, Equatable {
    let template: Template
    let isHighlighted: Bool
    let isActive: Bool
    let onHover: () -> Void
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    static func == (lhs: PaletteTemplateRow, rhs: PaletteTemplateRow) -> Bool {
        lhs.template == rhs.template
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Button(action: onSelect) {
            RowShell(isHighlighted: isHighlighted, onHoverEnter: onHover) {
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
