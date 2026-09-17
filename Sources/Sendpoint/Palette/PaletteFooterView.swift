import SendpointDomain
import SwiftUI

struct PaletteFooterView: View {
    let projection: PaletteProjection
    let flash: (text: String, generation: Int)?
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 18) {
            status
            Spacer()
            Button {
                onEvent(.toggleOverlay(.templates))
            } label: {
                HStack(spacing: 9) {
                    Text(projection.activeTemplate.name)
                        .font(.ui(12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Keycap("⌘P", size: 10.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Template used when copying (⌘P)")
            .accessibilityLabel("Template, \(projection.activeTemplate.name)")

            QuietButton("Actions", keys: "⌘K") {
                onEvent(.toggleOverlay(.actions))
            }
        }
        .animation(.easeOut(duration: 0.15), value: flash?.generation)
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: PaletteMetrics.barHeight)
    }

    @ViewBuilder
    private var status: some View {
        if let flash {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Ink.accent(scheme))
                Text(flash.text)
                    .font(.ui(12, weight: .medium))
            }
            .transition(.opacity)
        } else if projection.showsUndoInFooter, let undo = projection.undo {
            HStack(spacing: 12) {
                Text("Cleared \(noteCountLabel(undo.noteCount))")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                QuietButton("Undo", keys: "⌘Z") {
                    onEvent(.perform(.undoClear))
                }
            }
        } else if let current = projection.facts.current, let startedAt = current.startedAt {
            Text("\(current.countLabel) since \(noteTimeLabel(startedAt))")
                .font(.ui(12).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct PaletteProblemRow: View {
    let message: String
    let interaction: PaletteInteraction
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.uiCaption)
                .foregroundStyle(Ink.amber(scheme))
                .lineLimit(2)
            Spacer()
            if case .failed(_, _, true) = interaction {
                QuietButton("Retry") { onEvent(.retry) }
            } else if case .failed = interaction {
                QuietButton("Dismiss") { onEvent(.cancelEdit) }
            }
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }
}

struct PaletteErrorRow: View {
    let error: StackStoreError
    let hasPendingMutations: Bool
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Text(noteStoreErrorMessage(error))
                .font(.uiCaption)
                .foregroundStyle(Ink.amber(scheme))
                .lineLimit(2)
            Spacer()
            if hasPendingMutations {
                QuietButton("Retry") { onEvent(.retry) }
            }
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }
}
