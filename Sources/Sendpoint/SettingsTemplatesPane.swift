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
            SettingsPopUp(
                items: editor.templates.map { .init(id: $0.id, title: $0.name) },
                selectedID: editor.editedTemplateID,
                onSelect: { id in
                    guard let id else { return }
                    onSelectTemplate(id)
                }
            )
            .accessibilityLabel("Template")
            templateEditor
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsSection("Name") {
                TemplateNameField(text: $editor.draft.name) {
                    nameActions
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
    }

    private var nameActions: some View {
        HStack(spacing: 2) {
            QuietIconButton("plus") {
                newTemplate = NewTemplateDraft(name: "\(editor.draft.name) Copy")
            }
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
            if editor.canDelete {
                QuietIconButton("trash", hoverColor: .red) {
                    TemplateDialogs.delete(editor)
                }
                .help("Delete this template…")
                .accessibilityLabel("Delete template")
            }
        }
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
