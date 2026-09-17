import SwiftUI

/// One shortcut row: what it does, how, and the key that does it.
struct ShortcutSpec: Identifiable {
    let title: String
    var hint: String? = nil
    let slot: ShortcutSlot

    var id: ShortcutSlot { slot }
}

/// Shortcut rows for one page, with the recorder wired to the registrar.
/// A rebind that fails leaves the old keys and says why underneath.
struct ShortcutRows: View {
    let specs: [ShortcutSpec]
    @Bindable var shortcuts: ShortcutSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void

    @State private var feedback: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 { SettingsDivider() }
                SettingsRow(spec.title, hint: spec.hint) {
                    KeyRecorder(combo: binding(for: spec.slot), clearable: spec.slot.isOptional)
                        .fixedSize()
                }
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
                // A failed rebind leaves the old keys and explains why here.
                // The block reads as one element, and a new message is
                // announced politely (macOS SwiftUI has no live-region
                // modifier, so the announcement is posted explicitly).
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

    /// The error block's text as one string, so a change can be announced.
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
