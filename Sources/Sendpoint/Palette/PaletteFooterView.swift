import SendpointDomain
import SwiftUI

struct PaletteFooterView: View {
    let projection: PaletteProjection
    let flash: (text: String, generation: Int)?
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        browsingFooter(projection)
    }

    private func browsingFooter(_ projection: PaletteProjection) -> some View {
        HStack(spacing: 16) {
            if let flash {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.accent(scheme))
                    Text(flash.text)
                        .font(.ui(12, weight: .medium))
                }
                .transition(.opacity)
            } else {
                context(projection)
            }

            Spacer()

            Button {
                onEvent(.toggleOverlay(.templates))
            } label: {
                HStack(spacing: 7) {
                    Text("Template")
                        .font(.ui(12.5))
                        .foregroundStyle(.tertiary)
                    Text(projection.activeTemplate.name)
                        .font(.ui(12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 2)
                    Keycap("⌘P", size: 10.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Template used when copying (⌘P)")

            let primary = projection.primaryAction
            QuietButton(primary?.title ?? "Edit", keys: "↩") {
                if let primary { onEvent(.perform(primary.action)) }
            }
            .opacity(primary == nil ? 0 : 1)
            .disabled(primary == nil)
            .accessibilityHidden(primary == nil)

            QuietButton("Actions", keys: "⌘K") {
                onEvent(.toggleOverlay(.actions))
            }
        }
        .animation(.easeOut(duration: 0.15), value: flash?.generation)
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: PaletteMetrics.barHeight)
    }

    @ViewBuilder
    private func context(_ projection: PaletteProjection) -> some View {
        if let startedAt = projection.facts.current?.startedAt {
            Text("Started \(startedAt.formatted(.relative(presentation: .named)))")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct PaletteUndoBanner: View {
    let undo: StackUndoFacts
    let onEvent: (PaletteEvent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(undo.notification)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(undo.notification)
            QuietButton("Undo", keys: "⌘Z") {
                onEvent(.perform(.undoClear))
            }
            .help("Put the cleared notes back")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: 34)
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
