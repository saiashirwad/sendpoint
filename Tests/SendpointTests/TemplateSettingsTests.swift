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
        let editor = settings
        editor.send(.beginEditing)
        let cloneID = UUID()
        _ = try editor.send(.saveAsNew(name: "Custom", id: cloneID)).get()
        XCTAssertTrue(try XCTUnwrap(settings.template(id: cloneID)).clearStackAfterExport)

        editor.send(.editClearStackAfterExport(false))
        _ = try editor.send(.save).get()
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

        settings.send(.beginEditing)
        settings.send(.editPreamble(custom.preamble))
        settings.send(.editIncludeHeading(custom.includeHeading))
        settings.send(.editIncludeNoteNumbers(custom.includeNoteNumbers))
        _ = try settings.send(.saveAsNew(name: custom.name, id: custom.id)).get()
        let reloaded = TemplateSettings(defaults: defaults)

        XCTAssertEqual(reloaded.templates, Template.builtIns + [custom])
        XCTAssertEqual(reloaded.activeTemplateID, custom.id)
        XCTAssertEqual(reloaded.activeTemplate, custom)
    }

    func testDirtyExternalSelectionCancelKeepsDraftAndActiveTemplate() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Unsaved external draft"))

        XCTAssertEqual(editor.send(.request(.template(Template.plain.id))), .success(.needsDecision))
        XCTAssertEqual(editor.send(.resolve(.cancel)), .success(.cancelled))

        XCTAssertEqual(editor.draft.id, Template.learn.id)
        XCTAssertEqual(editor.draft.preamble, "Unsaved external draft")
        XCTAssertTrue(editor.isDirty)
        XCTAssertNil(editor.pendingDestination)
        XCTAssertEqual(settings.activeTemplateID, Template.learn.id)
    }

    func testCloseCancelAndFailedSaveKeepDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editName(Template.steer.name))

        XCTAssertEqual(editor.send(.request(.close)), .success(.needsDecision))
        XCTAssertEqual(editor.send(.resolve(.cancel)), .success(.cancelled))
        XCTAssertTrue(editor.isDirty)
        editor.send(.request(.close))
        XCTAssertEqual(editor.send(.resolve(.save)), .failure(.validation(.duplicateName)))
        XCTAssertEqual(editor.pendingDestination, .close)
        XCTAssertEqual(editor.draft.name, Template.steer.name)
        XCTAssertEqual(settings.template(id: Template.learn.id), .learn)
    }

    func testCloseDiscardAndSaveDecisionsResolveDirtyDraft() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Discard me"))

        editor.send(.request(.close))
        XCTAssertEqual(editor.send(.resolve(.discard)), .success(.closed))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .learn)

        editor.send(.editPreamble("Save me"))
        editor.send(.request(.close))
        XCTAssertEqual(editor.send(.resolve(.save)), .success(.closed))
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Save me")
    }

    func testDraftDoesNotAffectStoredTemplateUntilSaveAndCanRevert() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Changed"))

        XCTAssertTrue(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate, .learn)

        editor.send(.revert)
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(editor.draft, .learn)

        editor.send(.editPreamble("Saved"))
        _ = try editor.send(.save).get()
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(settings.activeTemplate.preamble, "Saved")
    }

    func testDirtyDiscardSwitchPersistsPendingTemplateAsActive() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Unsaved"))

        XCTAssertEqual(editor.send(.request(.template(Template.steer.id))), .success(.needsDecision))
        XCTAssertEqual(settings.activeTemplateID, Template.learn.id)
        editor.send(.resolve(.discard))

        XCTAssertEqual(editor.draft.id, Template.steer.id)
        XCTAssertEqual(editor.draft, .steer)
        XCTAssertEqual(settings.activeTemplateID, Template.steer.id)
        XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), Template.steer.id.uuidString)
    }

    func testDirtySaveSwitchOverwritesSourceThenActivatesTarget() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editName("Renamed Learn"))

        XCTAssertEqual(editor.send(.request(.template(Template.plain.id))), .success(.needsDecision))
        _ = try editor.send(.resolve(.save)).get()

        XCTAssertEqual(settings.template(id: Template.learn.id)?.name, "Renamed Learn")
        XCTAssertEqual(editor.draft.id, Template.plain.id)
        XCTAssertEqual(settings.activeTemplateID, Template.plain.id)
    }

    func testSaveAsNewClonesDraftWithNewIDWithoutMutatingSource() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Clone only"))

        let result = try editor.send(.saveAsNew(name: "  My Template  ", id: newID)).get()

        XCTAssertEqual(result, .changed)
        XCTAssertEqual(settings.template(id: Template.learn.id), .learn)
        XCTAssertEqual(settings.template(id: newID)?.name, "My Template")
        XCTAssertEqual(settings.template(id: newID)?.preamble, "Clone only")
        XCTAssertEqual(settings.activeTemplateID, newID)
        XCTAssertEqual(editor.draft.id, newID)
    }

    func testDeleteIsGuardedWhileDirtyAndDeletingActiveKeepsValidActiveID() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = try makeSettingsOnLearn(defaults)
        let editor = settings
        editor.send(.beginEditing)
        editor.send(.editPreamble("Dirty"))
        XCTAssertEqual(editor.send(.delete), .failure(.unsavedChanges))

        editor.send(.revert)
        _ = try editor.send(.delete).get()
        XCTAssertEqual(settings.templates.count, 2)
        XCTAssertFalse(settings.templates.contains(where: { $0.id == Template.learn.id }))
        XCTAssertEqual(settings.activeTemplateID, Template.steer.id)
        XCTAssertEqual(editor.draft.id, Template.steer.id)

        _ = try editor.send(.delete).get()
        XCTAssertEqual(settings.templates.count, 1)
        XCTAssertEqual(editor.send(.delete), .failure(.validation(.lastTemplate)))
        XCTAssertEqual(settings.activeTemplateID, settings.templates[0].id)
    }

    func testDraftFailedValidationAndTeardownDoNotPersistOrNotify() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        let committedData = defaults.data(forKey: "templates")
        let committedID = defaults.string(forKey: "activeTemplateID")
        var notifications = 0
        settings.onChange = { notifications += 1 }

        settings.send(.beginEditing)
        settings.send(.editName("learn"))
        settings.send(.editPreamble("Uncommitted"))
        settings.send(.request(.template(Template.steer.id)))
        XCTAssertEqual(settings.send(.resolve(.save)), .failure(.validation(.duplicateName)))
        XCTAssertEqual(settings.pendingDestination, .template(Template.steer.id))
        XCTAssertEqual(settings.activeTemplate, .plain)
        XCTAssertEqual(defaults.data(forKey: "templates"), committedData)
        XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), committedID)
        XCTAssertEqual(notifications, 0)

        settings.send(.endEditing)
        settings.send(.endEditing)
        settings.send(.save)
        settings.send(.resolve(.save))
        XCTAssertNil(settings.workspace.session)
        XCTAssertEqual(defaults.data(forKey: "templates"), committedData)
        XCTAssertEqual(defaults.string(forKey: "activeTemplateID"), committedID)
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(TemplateSettings(defaults: defaults).activeTemplate, .plain)
    }

    func testCommittedChangeNotifiesAfterPersistenceAndNavigation() throws {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = TemplateSettings(defaults: defaults)
        var published: [TemplateWorkspace] = []
        var persisted: [Data?] = []
        var persistedIDs: [String?] = []
        settings.onChange = { [weak settings] in
            guard let settings else { return }
            published.append(settings.workspace)
            persisted.append(defaults.data(forKey: "templates"))
            persistedIDs.append(defaults.string(forKey: "activeTemplateID"))
        }

        settings.send(.beginEditing)
        settings.send(.editPreamble("Saved source"))
        settings.send(.request(.template(Template.learn.id)))
        _ = try settings.send(.resolve(.save)).get()
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published[0].collection.template(id: Template.plain.id)?.preamble, "Saved source")
        XCTAssertEqual(published[0].session?.draft, .learn)
        XCTAssertNil(published[0].session?.pendingDestination)
        XCTAssertEqual(
            try JSONDecoder().decode([Template].self, from: XCTUnwrap(persisted[0])),
            published[0].collection.templates
        )
        XCTAssertEqual(persistedIDs[0], Template.learn.id.uuidString)

        let id = UUID()
        _ = try settings.send(.saveAsNew(name: "Copy", id: id)).get()
        XCTAssertEqual(published.count, 2)
        XCTAssertEqual(published[1].session?.draft.id, id)
        XCTAssertEqual(
            try JSONDecoder().decode([Template].self, from: XCTUnwrap(persisted[1])),
            published[1].collection.templates
        )
        XCTAssertEqual(persistedIDs[1], id.uuidString)
        settings.send(.endEditing)
        settings.send(.beginEditing)
        XCTAssertEqual(settings.draft.id, id)
        XCTAssertEqual(published.count, 2)
    }

    private enum Seed {
        case missing
        case empty
        case invalidData
    }

    private func makeSettingsOnLearn(_ defaults: UserDefaults) throws -> TemplateSettings {
        let settings = TemplateSettings(defaults: defaults)
        _ = try settings.send(.request(.template(Template.learn.id))).get()
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
