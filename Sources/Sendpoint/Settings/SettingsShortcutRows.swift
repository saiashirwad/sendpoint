import SwiftUI

struct ShortcutSpec: Identifiable {
    let title: String
    var hint: String? = nil
    let slot: ShortcutSlot

    var id: ShortcutSlot { slot }
}

struct ShortcutTitle: View {
    let spec: ShortcutSpec

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(spec.title)
                .font(.ui(14, weight: .medium))
            if let hint = spec.hint {
                Text(hint)
                    .font(.ui(13))
                    .foregroundStyle(Ink.secondaryStyle)
                    .lineLimit(1)
            }
        }
    }
}

struct ShortcutRows<Label: View>: View {
    let specs: [ShortcutSpec]
    @Bindable var shortcuts: ShortcutSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void
    @ViewBuilder let label: (ShortcutSpec) -> Label

    @State private var feedback: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let projection = ShortcutFeedback(
            slots: specs.map(\.slot),
            registrationIssues: shortcuts.shortcutRegistrationIssues,
            feedback: feedback
        )
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 { SettingsDivider() }
                HStack(alignment: .center, spacing: Spacing.md) {
                    label(spec)
                    Spacer(minLength: 12)
                    KeyRecorder(combo: binding(for: spec.slot), clearable: spec.slot.isOptional)
                        .fixedSize()
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
            }
            if projection.isVisible {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(projection.issues) { issue in
                        Text(issue.text)
                    }
                    if let feedback = projection.feedback {
                        Text(feedback)
                    }
                }
                .font(.ui(12.5))
                .foregroundStyle(Ink.amber(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.md)
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: projection.announcement) { _, message in
            announcePolitely(message)
        }
    }

    private func binding(for slot: ShortcutSlot) -> Binding<KeyCombo?> {
        Binding(
            get: { shortcuts.combo(for: slot) },
            set: { proposed in
                if let message = hotKeyRegistrar.updateShortcut(proposed, for: slot) {
                    feedback = message
                } else {
                    feedback = nil
                    onSettingsChanged()
                }
            }
        )
    }
}

extension ShortcutRows where Label == ShortcutTitle {
    init(specs: [ShortcutSpec], shortcuts: ShortcutSettings, hotKeyRegistrar: HotKeyRegistrar,
         onSettingsChanged: @escaping () -> Void) {
        self.init(specs: specs, shortcuts: shortcuts, hotKeyRegistrar: hotKeyRegistrar,
            onSettingsChanged: onSettingsChanged) { ShortcutTitle(spec: $0) }
    }
}
