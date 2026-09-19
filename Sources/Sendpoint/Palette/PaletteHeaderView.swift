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
        HStack(spacing: 14) {
            TextField("Search notes", text: $query)
                .textFieldStyle(.plain)
                .font(.ui(15))
                .focused(focus, equals: .search)
                .disabled(isSearchDisabled)

            if let matches = matchReadout {
                Text(matches)
                    .font(.mono(10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: matches)
                    .accessibilityLabel(matches.lowercased())
            }

            StackStrip(stacks: projection.facts.stacks, size: 13, accent: Ink.accent(scheme)) {
                onEvent(.selectStack($0))
            }
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: 48)
    }

    private var matchReadout: String? {
        guard query.nonblank != nil else { return nil }
        return "\(projection.noteListing.notes.count) OF \(projection.shownStack?.notes.count ?? 0)"
    }
}
