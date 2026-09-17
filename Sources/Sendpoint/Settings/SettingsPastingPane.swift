import SwiftUI

struct SettingsPastingPane: View {
    @Bindable var settings: AppSettings
    @Bindable var shortcuts: ShortcutSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let onSettingsChanged: () -> Void

    var body: some View {
        SettingsPage {
            SettingsSection("Output", footnote: outputFootnote) {
                SettingsStackedRow {
                    ChoiceChips(
                        values: [StackExportMode.paste, .copy],
                        selection: Binding(
                            get: { settings.stackExportMode },
                            set: {
                                settings.send(.exportMode($0))
                                onSettingsChanged()
                            }
                        ),
                        title: { $0 == .paste ? "Paste at the cursor" : "Copy to the clipboard" }
                    )
                }
            }
            SettingsSection("After a note") {
                SettingsToggleRow(
                    "Return to the previous app",
                    isOn: Binding(
                        get: { settings.restoreFocusAfterSave },
                        set: {
                            settings.send(.restoreFocusAfterSave($0))
                            onSettingsChanged()
                        }
                    )
                )
            }
            SettingsSection("Shortcuts") {
                ShortcutRows(
                    specs: [
                        ShortcutSpec(
                            title: settings.stackExportMode.shortcutTitle,
                            hint: settings.stackExportMode.shortcutHint,
                            slot: .copy
                        ),
                    ],
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                )
            }
        }
    }

    private var outputFootnote: String {
        switch settings.stackExportMode {
        case .paste: "The Markdown lands where your cursor is, in whatever app is in front."
        case .copy: "The Markdown replaces the clipboard, ready to paste anywhere."
        }
    }
}
