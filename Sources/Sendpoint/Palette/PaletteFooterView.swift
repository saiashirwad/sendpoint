import SendpointDomain
import SwiftUI

struct PaletteFooterView: View {
    let projection: PaletteProjection
    let flash: (text: String, generation: Int)?
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Spacing.lg) {
            status
            Spacer()
            Button {
                onEvent(.toggleOverlay(.templates))
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(projection.activeTemplate.name)
                        .font(.ui(12.5, weight: .medium))
                        .foregroundStyle(Ink.secondaryStyle)
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
        .animation(Motion.quick, value: flash?.generation)
        .padding(.horizontal, Spacing.xl)
        .frame(height: PaletteMetrics.barHeight)
    }

    @ViewBuilder
    private var status: some View {
        if let flash {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.symbol(10, weight: .bold))
                    .foregroundStyle(Ink.accent(scheme))
                Text(flash.text)
                    .font(.ui(12, weight: .medium))
            }
            .transition(.opacity)
        } else if projection.showsUndoInFooter, let undo = projection.undo {
            HStack(spacing: Spacing.md) {
                Text("Cleared \(noteCountLabel(undo.noteCount))")
                    .font(.ui(12))
                    .foregroundStyle(Ink.secondaryStyle)
                QuietButton("Undo", keys: "⌘Z") {
                    onEvent(.perform(.undoClear))
                }
            }
        } else if let current = projection.facts.current, let startedAt = current.startedAt {
            Text("\(current.countLabel) since \(noteTimestampLabel(startedAt))")
                .font(.ui(12).monospacedDigit())
                .foregroundStyle(Ink.secondaryStyle)
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
        HStack(spacing: Spacing.md) {
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
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
    }
}

struct PaletteErrorRow: View {
    let error: StackStoreError
    let hasPendingMutations: Bool
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(noteStoreErrorMessage(error))
                .font(.uiCaption)
                .foregroundStyle(Ink.amber(scheme))
                .lineLimit(2)
            Spacer()
            if hasPendingMutations {
                QuietButton("Retry") { onEvent(.retry) }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
    }
}
