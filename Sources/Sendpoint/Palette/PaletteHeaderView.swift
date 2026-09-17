import SendpointDomain
import SwiftUI

struct PaletteHeaderView: View {
    let projection: PaletteProjection
    @Binding var query: String
    let isSearchDisabled: Bool
    let focus: FocusState<PaletteField?>.Binding
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let facts = projection.facts
        HStack(spacing: 14) {
            if let current = facts.current {
                StackReadoutLabel(stack: current, numeralSize: 17, detailSize: 12)
                    .animation(.snappy(duration: 0.25), value: current.noteCount)
                    .fixedSize()
                Hairline(axis: .vertical).frame(height: 18)
            }

            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search notes", text: $query)
                .textFieldStyle(.plain)
                .font(.ui(15))
                .focused(focus, equals: .search)
                .disabled(isSearchDisabled)

            if let matches = matchReadout(projection) {
                Text(matches)
                    .font(.mono(10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: matches)
                    .accessibilityLabel(matches.lowercased())
            }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            StackStrip(stacks: facts.stacks, size: 12, accent: Ink.accent(scheme)) {
                onEvent(.selectStack($0))
            }
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: 48)
    }

    private func matchReadout(_ projection: PaletteProjection) -> String? {
        guard query.nonblank != nil else { return nil }
        return "\(projection.noteListing.notes.count) OF \(projection.shownStack?.notes.count ?? 0)"
    }
}
