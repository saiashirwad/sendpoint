import AppKit
import SendpointDomain
import SwiftUI

/// Templates as chips over one editor. The chip in ink is the template
/// being edited; a dot on it means the draft has unsaved changes.
struct SettingsTemplatesPane: View {
    @Bindable var settings: AppSettings
    @Bindable var editor: TemplateEditorState
    let onSelectTemplate: (UUID) -> Void

    @State private var newTemplate: NameDraft?
    @Environment(\.colorScheme) private var scheme

    private struct NameDraft: Equatable {
        var name: String
        var problem: String?
    }

    var body: some View {
        SettingsPage {
            SettingsSection("Template") {
                SettingsStackedRow {
                    chips
                }
            }
            SettingsSection("Name") {
                TextField("Template name", text: $editor.draft.name)
                    .textFieldStyle(.plain)
                    .font(.ui(14, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Ink.fill))
                    .padding(.vertical, 10)
                    .accessibilityLabel("Template name")
            }
            SettingsSection("Prompt", footnote: "Goes above the notes. Tell the AI what to do with them.") {
                TextField(
                    "Summarise these notes…",
                    text: $editor.draft.preamble,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.ui(13.5))
                .lineSpacing(4)
                .lineLimit(4...14)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Ink.fill))
                .padding(.vertical, 10)
                .accessibilityLabel("Prompt")
            }
            SettingsSection("Each note") {
                SettingsToggleRow("Number the notes", isOn: $editor.draft.includeNoteNumbers)
                SettingsDivider()
                SettingsToggleRow("Timestamps", isOn: $editor.draft.includeTimestamps)
            }
            SettingsSection(settings.stackExportMode.exportMomentCaption) {
                SettingsToggleRow("Date heading", isOn: $editor.draft.includeHeading)
                SettingsDivider()
                SettingsToggleRow("Clear the stack afterwards", isOn: $editor.draft.clearStackAfterExport)
            }
            HStack(spacing: 16) {
                if editor.isDirty {
                    InkButton("Save", keys: "⌘S", action: save)
                        .keyboardShortcut("s", modifiers: .command)
                    QuietButton("Revert", action: editor.revert)
                }
                Spacer(minLength: 0)
                if editor.canDelete {
                    QuietButton("Delete template", hoverColor: Ink.accent(scheme)) {
                        TemplateDialogs.delete(editor)
                    }
                }
            }
            .padding(.top, -8)
            .animation(.easeOut(duration: 0.15), value: editor.isDirty)
        }
    }

    private var chips: some View {
        FlowLayout(spacing: 8) {
            ForEach(editor.templates) { template in
                let isEdited = template.id == editor.editedTemplateID
                Chip(
                    title: isEdited ? (editor.draft.name.nonblank ?? template.name) : template.name,
                    isSelected: isEdited,
                    isDirty: isEdited && editor.isDirty
                ) {
                    onSelectTemplate(template.id)
                }
            }
            AddChip(label: "New template") {
                newTemplate = NameDraft(name: "\(editor.draft.name) Copy")
            }
            .popover(
                isPresented: Binding(
                    get: { newTemplate != nil },
                    set: { if !$0 { newTemplate = nil } }
                ),
                arrowEdge: .bottom
            ) {
                NamePopover(
                    prompt: "New template from the current draft",
                    placeholder: "Template name",
                    name: Binding(
                        get: { newTemplate?.name ?? "" },
                        set: { newTemplate?.name = $0; newTemplate?.problem = nil }
                    ),
                    problem: newTemplate?.problem,
                    onCommit: create
                )
            }
        }
    }

    private func save() {
        do { try editor.save() } catch { TemplateDialogs.showError(error) }
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
