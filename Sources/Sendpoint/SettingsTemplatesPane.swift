import SendpointDomain
import SwiftUI

struct SettingsTemplatesPane: View {
    @Bindable var settings: AppSettings
    @Bindable var editor: TemplateEditorState
    let onSelectTemplate: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            templateChips
            templateEditor
        }
    }

    private var templateChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCaption("Active template")
            HStack(spacing: 6) {
                ForEach(editor.templates) { template in
                    TemplateChip(
                        name: template.name,
                        isSelected: template.id == editor.editedTemplateID,
                        isDirty: template.id == editor.editedTemplateID && editor.isDirty
                    ) {
                        onSelectTemplate(template.id)
                    }
                }
            }
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsSection("Name") {
                TemplateNameField(text: $editor.draft.name)
            }
            SettingsSection("Prompt") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $editor.draft.preamble)
                        .font(.body)
                        .lineSpacing(2)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(minHeight: 140, maxHeight: 140)
                        .accessibilityLabel("Prompt")
                    if editor.draft.preamble.isEmpty {
                        Text("Tell the AI what to do with the notes below.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .insetSurface(radius: SettingsMetrics.cardRadius)
            }
            SettingsSection("Each note") {
                SettingsRowGroup {
                    SettingsToggleRow("Number each note", isOn: $editor.draft.includeNoteNumbers)
                    SettingsDivider(pastIcon: false)
                    SettingsToggleRow("Time", isOn: $editor.draft.includeTimestamps)
                }
            }
            SettingsSection(settings.stackExportMode.exportMomentCaption) {
                SettingsRowGroup {
                    SettingsToggleRow("Date heading at the top", isOn: $editor.draft.includeHeading)
                    SettingsDivider(pastIcon: false)
                    SettingsToggleRow("Clear the stack afterwards", isOn: $editor.draft.clearStackAfterExport)
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: editor.isDirty)
    }
}
