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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(spec.title)
                .font(.ui(14, weight: .medium))
            if let hint = spec.hint {
                Text(hint)
                    .font(.ui(13))
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 { SettingsDivider() }
                HStack(alignment: .center, spacing: 12) {
                    label(spec)
                    Spacer(minLength: 12)
                    KeyRecorder(combo: binding(for: spec.slot), clearable: spec.slot.isOptional)
                        .fixedSize()
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
            }
            if !issues.isEmpty || feedback != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { issue in
                        Text("\(issue.id.title): \(issue.message)")
                    }
                    if let feedback {
                        Text(feedback)
                    }
                }
                .font(.ui(12.5))
                .foregroundStyle(Ink.amber(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: errorMessage ?? "") { _, message in
            announcePolitely(message)
        }
    }

    private var issues: [ShortcutRegistrationIssue] {
        let slots = Set(specs.map(\.slot))
        return shortcuts.shortcutRegistrationIssues.filter { slots.contains($0.id) }
    }

    private var errorMessage: String? {
        let parts = issues.map { "\($0.id.title): \($0.message)" } + (feedback.map { [$0] } ?? [])
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
