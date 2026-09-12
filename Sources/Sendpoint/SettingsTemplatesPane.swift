import AppKit
import SendpointDomain
import SwiftUI

struct SettingsTemplatesPane: View {
    @Bindable var settings: AppSettings
    @Bindable var editor: TemplateEditorState
    let onSelectTemplate: (UUID) -> Void
    @State private var newTemplate: NewTemplateDraft?

    private struct NewTemplateDraft: Equatable {
        var name: String
        var problem: String?
    }

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
                newTemplateChip
            }
        }
    }

    private var newTemplateChip: some View {
        Button {
            newTemplate = NewTemplateDraft(name: "\(editor.draft.name) Copy")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("New")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .foregroundStyle(.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("New template from this draft…")
        .accessibilityLabel("New template")
        .popover(
            isPresented: Binding(
                get: { newTemplate != nil },
                set: { if !$0 { newTemplate = nil } }
            ),
            arrowEdge: .bottom
        ) {
            NewTemplatePopover(
                name: Binding(
                    get: { newTemplate?.name ?? "" },
                    set: { newTemplate?.name = $0; newTemplate?.problem = nil }
                ),
                problem: newTemplate?.problem,
                onCommit: create
            )
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            TemplateNameField(text: $editor.draft.name) {
                if editor.canDelete {
                    QuietDeleteButton {
                        TemplateDialogs.delete(editor)
                    }
                }
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

    private func create() {
        guard let draft = newTemplate else { return }
        do {
            let name = try editor.validatedNewTemplateName(draft.name)
            _ = try editor.saveAsNew(named: name)
            newTemplate = nil
        } catch {
            newTemplate?.problem = error.localizedDescription
            NSSound.beep()
        }
    }
}
