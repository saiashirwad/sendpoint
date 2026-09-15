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
            }
        }
    }

    private var issues: [ShortcutRegistrationIssue] {
        let slots = Set(specs.map(\.slot))
        return shortcuts.shortcutRegistrationIssues.filter { slots.contains($0.id) }
    }

    private func binding(for slot: ShortcutSlot) -> Binding<KeyCombo?> {
        Binding(
            get: { shortcuts.combo(for: slot) },
            set: { proposed in
                guard let proposed else {
                    hotKeyRegistrar.clear(slot)
                    feedback = nil
                    onSettingsChanged()
                    return
                }
                do {
                    try hotKeyRegistrar.rebind(proposed, for: slot)
                    feedback = nil
                    onSettingsChanged()
                } catch {
                    feedback = error.localizedDescription
                }
            }
        )
    }
}
