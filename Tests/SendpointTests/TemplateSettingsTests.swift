import SendpointDomain
import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class TemplateSettingsTests: XCTestCase {
    func testFreshDefaultsPersistReplacementTemplatesAndClearFlags() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let saved = try JSONDecoder().decode([Template].self, from: XCTUnwrap(defaults.data(forKey: "templates")))

        XCTAssertEqual(settings.templates.map(\.name), ["Plain", "Learn", "Steer"])
        XCTAssertEqual(saved, [.plain, .learn, .steer])
        XCTAssertTrue(saved.allSatisfy(\.clearStackAfterExport))
        XCTAssertEqual(settings.activeTemplate, .plain)
    }

    func testSaveAsNewDefaultsToClearingAndAllowsOptingOut() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let editor = TemplateEditorController(settings: settings)
        let cloneID = try editor.saveAsNew(named: "Custom")
        XCTAssertTrue(try XCTUnwrap(settings.template(id: cloneID)).clearStackAfterExport)

        editor.send(.editClearStackAfterExport(false))
        try editor.save()
        let reloaded = TemplateSettings(defaults: defaults)
        XCTAssertFalse(try XCTUnwrap(reloaded.template(id: cloneID)).clearStackAfterExport)
    }

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
                defaults.set(Template.learn.id.uuidString, forKey: "activeTemplateID")
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
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editPreamble("Unsaved external draft"))

        XCTAssertEqual(editor.requestSelection(Template.plain.id), .needsDecision)
        XCTAssertFalse(try editor.resolvePendingSelection(.cancel))

        XCTAssertEqual(editor.editedTemplateID, Template.learn.id)
        XCTAssertEqual(editor.draft.preamble, "Unsaved external draft")
        XCTAssertTrue(editor.isDirty)
        XCTAssertNil(editor.pendingTemplateID)
        XCTAssertEqual(settings.activeTemplateID, Template.learn.id)
    }

    func testCloseCancelAndFailedSaveKeepDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editName(Template.steer.name))

        XCTAssertFalse(try editor.resolveClose(.cancel))
        XCTAssertTrue(editor.isDirty)
        XCTAssertThrowsError(try editor.resolveClose(.save)) {
            XCTAssertEqual($0 as? TemplateError, .duplicateName)
        }
        XCTAssertEqual(editor.draft.name, Template.steer.name)
        XCTAssertEqual(settings.template(id: Template.learn.id), .learn)
    }

    func testCloseDiscardAndSaveDecisionsResolveDirtyDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editPreamble("Discard me"))

        XCTAssertTrue(try editor.resolveClose(.discard))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .learn)

        editor.send(.editPreamble("Save me"))
        XCTAssertTrue(try editor.resolveClose(.save))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Save me")
    }

    func testDraftDoesNotAffectStoredTemplateUntilSaveAndCanRevert() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editPreamble("Changed"))

        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate, .learn)

        editor.revert()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .learn)

        editor.send(.editPreamble("Saved"))
        try editor.save()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Saved")
    }

    func testDirtyDiscardSwitchPersistsPendingTemplateAsActive() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editPreamble("Unsaved"))

        XCTAssertEqual(editor.requestSelection(Template.steer.id), .needsDecision)
        XCTAssertEqual(settings.activeTemplateID, Template.learn.id)
        editor.discardAndSelectPending()

        XCTAssertEqual(editor.editedTemplateID, Template.steer.id)
        XCTAssertEqual(editor.draft, .steer)
        XCTAssertEqual(settings.activeTemplateID, Template.steer.id)
        XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), Template.steer.id.uuidString)
    }

    func testDirtySaveSwitchOverwritesSourceThenActivatesTarget() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editName("Renamed Learn"))

        XCTAssertEqual(editor.requestSelection(Template.plain.id), .needsDecision)
        try editor.saveAndSelectPending()

        XCTAssertEqual(settings.template(id: Template.learn.id)?.name, "Renamed Learn")
        XCTAssertEqual(editor.editedTemplateID, Template.plain.id)
        XCTAssertEqual(settings.activeTemplateID, Template.plain.id)
    }

    func testSaveAsNewClonesDraftWithNewIDWithoutMutatingSource() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let editor = TemplateEditorController(settings: settings, makeID: { newID })
        editor.send(.editPreamble("Clone only"))

        let result = try editor.saveAsNew(named: "  My Template  ")

        XCTAssertEqual(result, newID)
        XCTAssertEqual(settings.template(id: Template.learn.id), .learn)
        XCTAssertEqual(settings.template(id: newID)?.name, "My Template")
        XCTAssertEqual(settings.template(id: newID)?.preamble, "Clone only")
        XCTAssertEqual(settings.activeTemplateID, newID)
        XCTAssertEqual(editor.editedTemplateID, newID)
    }

    func testDeleteIsGuardedWhileDirtyAndDeletingActiveKeepsValidActiveID() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = TemplateEditorController(settings: settings)
        editor.send(.editPreamble("Dirty"))
        XCTAssertThrowsError(try editor.delete()) {
            XCTAssertEqual($0 as? TemplateEditorError, .unsavedChanges)
        }

        editor.revert()
        try editor.delete()
        XCTAssertEqual(settings.templates.count, 2)
        XCTAssertFalse(settings.templates.contains(where: { $0.id == Template.learn.id }))
        XCTAssertEqual(settings.activeTemplateID, Template.steer.id)
        XCTAssertEqual(editor.editedTemplateID, Template.steer.id)

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

    private func makeSettingsOnLearn(_ defaults: UserDefaults) throws -> TemplateSettings {
        let settings = TemplateSettings(defaults: defaults)
        try settings.selectTemplate(id: Template.learn.id)
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
