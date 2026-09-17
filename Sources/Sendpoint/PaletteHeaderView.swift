import SendpointDomain
import SwiftUI

/// The palette's search header: a magnifier, the query field (or the static
/// "Switch stack" title while cycling), the match readout, and the clear
/// button. Takes the shell-threaded projection plus small scalars; the
/// query binding writes straight back to the model.
struct PaletteHeaderView: View {
    let projection: PaletteProjection
    @Binding var query: String
    let presentation: PalettePresentation
    let focusedPane: PalettePane
    let isSearchDisabled: Bool
    let focus: FocusState<PaletteField?>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            if presentation == .cycling {
                Text("Switch stack")
                    .font(.ui(15, weight: .medium))
                Spacer()
            } else {
                TextField(projection.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.ui(15))
                    .focused(focus, equals: .search)
                    .disabled(isSearchDisabled)
            }

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
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: 48)
    }

    /// "3 OF 12" while a search narrows the focused pane.
    private func matchReadout(_ projection: PaletteProjection) -> String? {
        guard query.nonblank != nil, presentation != .cycling else { return nil }
        let (matches, total): (Int, Int) = switch focusedPane {
        case .stacks: (projection.stackListing.stacks.count, projection.facts.stacks.count)
        case .notes: (projection.noteListing.notes.count, projection.shownStack?.notes.count ?? 0)
        }
        return "\(matches) OF \(total)"
    }
}
