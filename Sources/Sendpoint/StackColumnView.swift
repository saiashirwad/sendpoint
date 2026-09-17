import SwiftUI

/// The palette's stack sidebar: the scrollable stack rows plus the offer to
/// create a stack, with the pinned new-stack row at its foot. Takes the
/// shell-threaded projection plus small scalars; events leave via onEvent.
struct StackColumnView: View {
    let projection: PaletteProjection
    let query: String
    let highlight: QuickSwitchRow?
    let focusedPane: PalettePane
    let presentation: PalettePresentation
    let inlineEdit: PaletteEdit?
    let rowHeight: CGFloat
    let stackNamespace: Namespace.ID
    let dotNamespace: Namespace.ID
    let focus: FocusState<PaletteField?>.Binding
    let onEvent: (PaletteEvent) -> Void

    var body: some View {
        let listing = projection.stackListing
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
                            Text("Nothing called “\(query.trimmingCharacters(in: .whitespaces))”.")
                                .font(.uiCallout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, PaletteMetrics.horizontalPadding)
                                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 6)
                }
                // One focus section for the sidebar rows. While browsing with
                // a row Button focused, the global monitor declines arrows so
                // this section owns them via RowMoveCommands (the SAME .key
                // events the monitor path sends); Tab, ↩, and Esc stay
                // monitor-owned in every focus state. Disabled while editing
                // so rename-field arrows reach their field exactly as today
                // (a present-but-idle handler would still swallow them).
                .focusSection()
                .modifier(RowMoveCommands(enabled: inlineEdit == nil, onEvent: onEvent))
                .onChange(of: highlight) {
                    guard let highlight else { return }
                    withAnimation(StackPaletteView.travel) { proxy.scrollTo(highlight, anchor: nil) }
                }
            }
            Hairline()
            newStackRow
        }
        .contentShape(Rectangle())
        .onTapGesture { onEvent(.focusPane(.stacks)) }
    }

    /// The pinned row at the foot of the sidebar: a click, ⌘N, or a typed
    /// name all lead here. It swaps to the name field while creating.
    @ViewBuilder
    private var newStackRow: some View {
        if case .createStack = inlineEdit {
            inlineCreateRow
        } else {
            Button {
                onEvent(.perform(.newStack))
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
                .padding(.horizontal, PaletteMetrics.horizontalPadding)
                .frame(height: PaletteMetrics.barHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Create a stack (⌘N)")
        }
    }

    private func stackRow(_ stack: StackItemFacts, position: Int) -> some View {
        let isHighlighted = highlight == .stack(stack.id)
        var isRenaming = false
        if case let .renameStack(id, _, _) = inlineEdit, id == stack.id { isRenaming = true }
        let showsDigit = focusedPane == .stacks && presentation != .cycling
        return PaletteStackRow(
            stack: stack,
            position: position,
            showsDigit: showsDigit,
            isHighlighted: isHighlighted,
            isDimmed: focusedPane != .stacks,
            isRenaming: isRenaming,
            renameText: isRenaming ? (inlineEdit?.text ?? "") : "",
            focus: focus,
            stackNamespace: stackNamespace,
            dotNamespace: dotNamespace,
            onSelect: { onEvent(.chooseStack(stack.id)) },
            onActivate: { onEvent(.perform(.switchToStack(stack.id))) },
            onEditText: { onEvent(.editText($0)) }
        )
        .equatable()
        .frame(height: rowHeight)
        // The current-stack dot (a matchedGeometryEffect inside StackRowName)
        // still needs a spring transaction when currentStackID changes, but
        // scoped to the affected rows only: the value is per-row, so only the
        // old and new current rows animate instead of the whole sidebar.
        .animation(StackPaletteView.travel, value: stack.isCurrent)
    }

    private func createRow(_ name: String) -> some View {
        let isHighlighted = highlight == .create(name)
        return PaletteCreateRow(
            name: name,
            isHighlighted: isHighlighted,
            isDimmed: focusedPane != .stacks,
            namespace: stackNamespace,
            onSelect: { onEvent(.chooseCreate(name)) },
            onActivate: { onEvent(.perform(.createStack(name))) }
        )
        .equatable()
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
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: PaletteMetrics.barHeight)
        .background(Rectangle().fill(Ink.selection))
    }

    /// The name being typed. A problem with it is reported once, in the
    /// problem row under the panes, where it has room and its buttons.
    private func inlineNameField(field: PaletteField, placeholder: String) -> some View {
        TextField(
            placeholder,
            text: Binding(
                get: { (inlineEdit?.text ?? "") },
                set: { onEvent(.editText($0)) }
            )
        )
        .textFieldStyle(.plain)
        .font(.ui(13.5, weight: .medium))
        .focused(focus, equals: field)
    }
}
