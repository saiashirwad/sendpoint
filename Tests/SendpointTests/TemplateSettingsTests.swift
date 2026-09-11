import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class TemplateSettingsTests: XCTestCase {
    func testMissingEmptyAndInvalidTemplateDataFallBackToBuiltInsAndPlain() throws {
        for seed in [Seed.missing, .empty, .invalidData] {
            let defaults = makeDefaults()
            defer { remove(defaults) }
            switch seed {
            case .missing:
                break
            case .empty:
                defaults.set(try JSONEncoder().encode([Template]()), forKey: "templates")
                defaults.set(UUID().uuidString, forKey: "activeTemplateID")
            case .invalidData:
                defaults.set(Data("not json".utf8), forKey: "templates")
                defaults.set(Template.coherent.id.uuidString, forKey: "activeTemplateID")
            }

            let settings = TemplateSettings(defaults: defaults)

            XCTAssertEqual(settings.templates, Template.builtIns)
            XCTAssertEqual(settings.activeTemplateID, Template.plain.id)
            XCTAssertEqual(settings.activeTemplate, .plain)
            XCTAssertNotNil(defaults.data(forKey: "templates"))
            XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), Template.plain.id.uuidString)
        }
    }

    func testValidTemplatesAndActiveTemplatePersistAcrossSettingsInstances() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        var custom = Template.plain
        custom = Template(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "Custom",
            preamble: "Custom preamble",
            includeTimestamps: false,
            includeHeading: true,
            includeNoteNumbers: true,
            clearStackAfterExport: true
        )

        try settings.addTemplate(custom)
        try settings.selectTemplate(id: custom.id)
        let reloaded = TemplateSettings(defaults: defaults)

        XCTAssertEqual(reloaded.templates, Template.builtIns + [custom])
        XCTAssertEqual(reloaded.activeTemplateID, custom.id)
        XCTAssertEqual(reloaded.activeTemplate, custom)
    }

    func testDirtyExternalSelectionCancelKeepsDraftAndActiveTemplate() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.preamble = "Unsaved external draft"

        XCTAssertEqual(editor.requestSelection(Template.plain.id), .needsDecision)
        XCTAssertFalse(try editor.resolvePendingSelection(.cancel))

        XCTAssertEqual(editor.editedTemplateID, Template.coherent.id)
        XCTAssertEqual(editor.draft.preamble, "Unsaved external draft")
        XCTAssertTrue(editor.isDirty)
        XCTAssertNil(editor.pendingTemplateID)
        XCTAssertEqual(settings.activeTemplateID, Template.coherent.id)
    }

    func testCloseCancelAndFailedSaveKeepDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.name = Template.pointByPoint.name

        XCTAssertFalse(try editor.resolveClose(.cancel))
        XCTAssertTrue(editor.isDirty)
        XCTAssertThrowsError(try editor.resolveClose(.save)) {
            XCTAssertEqual($0 as? TemplateError, .duplicateName)
        }
        XCTAssertEqual(editor.draft.name, Template.pointByPoint.name)
        XCTAssertEqual(settings.template(id: Template.coherent.id), .coherent)
    }

    func testCloseDiscardAndSaveDecisionsResolveDirtyDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.preamble = "Discard me"

        XCTAssertTrue(try editor.resolveClose(.discard))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .coherent)

        editor.draft.preamble = "Save me"
        XCTAssertTrue(try editor.resolveClose(.save))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Save me")
    }

    func testDraftDoesNotAffectStoredTemplateUntilSaveAndCanRevert() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.preamble = "Changed"

        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate, .coherent)

        editor.revert()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .coherent)

        editor.draft.preamble = "Saved"
        try editor.save()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Saved")
    }

    func testDirtyDiscardSwitchPersistsPendingTemplateAsActive() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.preamble = "Unsaved"

        XCTAssertEqual(editor.requestSelection(Template.pointByPoint.id), .needsDecision)
        XCTAssertEqual(settings.activeTemplateID, Template.coherent.id)
        editor.discardAndSelectPending()

        XCTAssertEqual(editor.editedTemplateID, Template.pointByPoint.id)
        XCTAssertEqual(editor.draft, .pointByPoint)
        XCTAssertEqual(settings.activeTemplateID, Template.pointByPoint.id)
        XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), Template.pointByPoint.id.uuidString)
    }

    func testDirtySaveSwitchOverwritesSourceThenActivatesTarget() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.name = "Renamed Coherent"

        XCTAssertEqual(editor.requestSelection(Template.plain.id), .needsDecision)
        try editor.saveAndSelectPending()

        XCTAssertEqual(settings.template(id: Template.coherent.id)?.name, "Renamed Coherent")
        XCTAssertEqual(editor.editedTemplateID, Template.plain.id)
        XCTAssertEqual(settings.activeTemplateID, Template.plain.id)
    }

    func testSaveAsNewClonesDraftWithNewIDWithoutMutatingSource() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let editor = TemplateEditorState(settings: settings, makeID: { newID })
        editor.draft.preamble = "Clone only"

        let result = try editor.saveAsNew(named: "  My Template  ")

        XCTAssertEqual(result, newID)
        XCTAssertEqual(settings.template(id: Template.coherent.id), .coherent)
        XCTAssertEqual(settings.template(id: newID)?.name, "My Template")
        XCTAssertEqual(settings.template(id: newID)?.preamble, "Clone only")
        XCTAssertEqual(settings.activeTemplateID, newID)
        XCTAssertEqual(editor.editedTemplateID, newID)
    }

    func testDeleteIsGuardedWhileDirtyAndDeletingActiveKeepsValidActiveID() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnCoherent(defaults)
        let editor = TemplateEditorState(settings: settings)
        editor.draft.preamble = "Dirty"
        XCTAssertThrowsError(try editor.delete()) {
            XCTAssertEqual($0 as? TemplateEditorError, .unsavedChanges)
        }

        editor.revert()
        try editor.delete()
        XCTAssertEqual(settings.templates.count, 2)
        XCTAssertFalse(settings.templates.contains(where: { $0.id == Template.coherent.id }))
        XCTAssertEqual(settings.activeTemplateID, Template.pointByPoint.id)
        XCTAssertEqual(editor.editedTemplateID, Template.pointByPoint.id)

        try editor.delete()
        XCTAssertEqual(settings.templates.count, 1)
        XCTAssertThrowsError(try editor.delete()) {
            XCTAssertEqual($0 as? TemplateError, .lastTemplate)
        }
        XCTAssertEqual(settings.activeTemplateID, settings.templates[0].id)
    }

    private enum Seed {
        case missing
        case empty
        case invalidData
    }

    /// Editor flows below edit Coherent; a fresh store opens on Plain.
    private func makeSettingsOnCoherent(_ defaults: UserDefaults) throws -> TemplateSettings {
        let settings = TemplateSettings(defaults: defaults)
        try settings.selectTemplate(id: Template.coherent.id)
        return settings
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "TemplateSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(suite, forKey: "testSuiteName")
        return defaults
    }

    private func remove(_ defaults: UserDefaults) {
        guard let suite = defaults.string(forKey: "testSuiteName") else { return }
        defaults.removePersistentDomain(forName: suite)
    }
}
