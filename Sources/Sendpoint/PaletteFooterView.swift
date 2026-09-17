import SendpointDomain
import SwiftUI

/// The palette's footer: the cycling hints while switching stacks, or the
/// flash/context line plus the template picker and primary/⌘K actions.
/// Takes the shell-threaded projection plus small scalars.
struct PaletteFooterView: View {
    let projection: PaletteProjection
    let presentation: PalettePresentation
    let focusedPane: PalettePane
    let flash: (text: String, generation: Int)?
    let switchComboLabel: String
    let onEvent: (PaletteEvent) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if presentation == .cycling {
            HStack(spacing: 14) {
                hint(switchComboLabel, "cycle")
                hint("⇧", "reverse")
                Spacer()
                Text("Release to switch")
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, PaletteMetrics.horizontalPadding)
            .frame(height: PaletteMetrics.barHeight)
        } else {
            browsingFooter(projection)
        }
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

            if let primary = projection.primaryAction {
                QuietButton(primary.verb, keys: "↩") {
                    onEvent(.perform(primary.action))
                }
            }

            QuietButton("Actions", keys: "⌘K") {
                onEvent(.toggleOverlay(.actions))
            }
        }
        .animation(.easeOut(duration: 0.15), value: flash?.generation)
        .padding(.horizontal, PaletteMetrics.horizontalPadding)
        .frame(height: PaletteMetrics.barHeight)
    }

    /// Where the keyboard is and how to move it.
    private func context(_ projection: PaletteProjection) -> some View {
        HStack(spacing: 12) {
            switch focusedPane {
            case .stacks:
                let count = projection.facts.stacks.count
                Text("\(count) stack\(count == 1 ? "" : "s")")
                hint("⇥", "notes")
            case .notes:
                let count = projection.shownStack?.notes.count ?? 0
                Text("\(projection.shownStack?.name ?? "") · \(noteCountLabel(count))")
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy(duration: 0.3), value: count)
                hint("⇥", "stacks")
            }
        }
        .font(.uiCaption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(keys, size: 10, isMuted: true)
            Text(label)
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// The banner offering to put cleared notes back.
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

/// A validation or save problem, with Retry when the failure is retryable
/// and Dismiss when it is not.
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

/// A store error, with Retry while mutations are still pending.
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
