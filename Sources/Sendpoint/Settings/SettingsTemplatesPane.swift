import AppKit
import SendpointDomain
import SwiftUI

struct SettingsTemplatesPane: View {
    @Bindable var settings: AppSettings
    @Bindable var editor: TemplateEditorController
    let onSelectTemplate: (UUID) -> Void

    @State private var newTemplate: NameDraft?

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
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection("Name") {
                    HStack(alignment: .center, spacing: 0) {
                        TextField("Template name", text: Binding(
                            get: { editor.draft.name },
                            set: { editor.send(.editName($0)) }
                        ))
                            .textFieldStyle(.plain)
                            .font(.ui(14, weight: .medium))
                            .padding(.horizontal, Spacing.md)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Ink.fill))
                            .accessibilityLabel("Template name")
                            .padding(.trailing, Spacing.sm)
                        if editor.isDirty {
                            GlyphButton(label: "Save", isProminent: true, action: save) { FloppyGlyph() }
                                .keyboardShortcut("s", modifiers: .command)
                                .help("Save  ⌘S")
                                .transition(.opacity)
                            GlyphButton(systemName: "arrow.counterclockwise", label: "Revert", action: editor.revert)
                                .help("Revert changes")
                                .transition(.opacity)
                        }
                        GlyphButton(systemName: "trash", label: "Delete") { TemplateDialogs.delete(editor) }
                            .disabled(!editor.canDelete)
                            .help(editor.canDelete ? "Delete this template" : "The last template cannot be deleted")
                    }
                    .padding(.top, Spacing.md)
                    .padding(.trailing, -Spacing.sm)
                    .animation(Motion.quick, value: editor.isDirty)
                }
                SettingsSection("Prompt") {
                    TextField(
                        "Summarise these notes…",
                        text: Binding(
                            get: { editor.draft.preamble },
                            set: { editor.send(.editPreamble($0)) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.ui(13.5))
                    .lineSpacing(4)
                    .lineLimit(4...14)
                    .padding(Spacing.md)
                    .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Ink.fill))
                    .padding(.top, Spacing.md)
                    .accessibilityLabel("Prompt")
                }
            }
            VStack(spacing: 0) {
                SettingsToggleRow("Number the notes", isOn: Binding(
                    get: { editor.draft.includeNoteNumbers },
                    set: { editor.send(.editIncludeNoteNumbers($0)) }
                ))
                SettingsDivider()
                SettingsToggleRow("Timestamps", isOn: Binding(
                    get: { editor.draft.includeTimestamps },
                    set: { editor.send(.editIncludeTimestamps($0)) }
                ))
                SettingsDivider()
                SettingsToggleRow("Date heading", isOn: Binding(
                    get: { editor.draft.includeHeading },
                    set: { editor.send(.editIncludeHeading($0)) }
                ))
                SettingsDivider()
                SettingsToggleRow(settings.stackExportMode.clearAfterExportTitle, isOn: Binding(
                    get: { editor.draft.clearStackAfterExport },
                    set: { editor.send(.editClearStackAfterExport($0)) }
                ))
            }
        }
    }

    private var chips: some View {
        FlowLayout(spacing: Spacing.sm) {
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
