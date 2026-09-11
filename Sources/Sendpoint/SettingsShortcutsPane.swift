import SwiftUI

struct SettingsShortcutIssues: View {
    let issues: [ShortcutRegistrationIssue]

    var body: some View {
        SettingsRowGroup {
            VStack(alignment: .leading, spacing: 6) {
                Label("Shortcut unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                ForEach(issues) { issue in
                    Text("• \(issue.id.title): \(issue.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsMetrics.rowInset)
        }
    }
}

struct SettingsShortcutsPane: View {
    @Bindable var settings: AppSettings
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsSection("Making notes") {
                SettingsRowGroup {
                    shortcutRow(
                        icon: "mic.fill",
                        title: "Voice note",
                        detail: voiceSettings.voiceMode.detail,
                        slot: .voiceCapture
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "square.and.pencil",
                        title: "Typed note",
                        detail: "A note box for the selected text.",
                        slot: .capture
                    )
                }
            }
            SettingsSection("Your stack") {
                SettingsRowGroup {
                    shortcutRow(
                        icon: "doc.on.clipboard",
                        title: settings.stackExportMode.shortcutTitle,
                        detail: settings.stackExportMode.shortcutDetail,
                        slot: .copy
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "square.stack.3d.up",
                        title: "Show stack",
                        detail: "Opens the window with all your notes.",
                        slot: .stack
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "arrow.left.arrow.right",
                        title: "Switch stack",
                        detail: "Tap or hold to cycle stacks; ↑/↓ lists all.",
                        slot: .switchStack
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "arrow.right.to.line",
                        title: "Next stack",
                        detail: "Steps through stacks; ⌫ removes while recording.",
                        slot: .nextStack
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "arrow.left.to.line",
                        title: "Previous stack",
                        detail: "The same walk, backwards.",
                        slot: .previousStack
                    )
                    SettingsDivider()
                    shortcutRow(
                        icon: "trash",
                        title: "Clear stack",
                        detail: "Empties the stack. Undo with ⌘Z.",
                        slot: .clear
                    )
                }
            }
            if let feedback {
                Label(feedback, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutRow(
        icon: String,
        title: String,
        detail: String,
        slot: ShortcutSlot
    ) -> some View {
        SettingsIconRow(icon: icon, title: title, detail: detail) {
            KeyRecorder(combo: binding(for: slot), clearable: slot.isOptional)
                .fixedSize()
        }
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
