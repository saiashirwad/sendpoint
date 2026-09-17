import AppKit
import Carbon.HIToolbox
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StatusMenuModelTests: XCTestCase {
    @MainActor private struct FixtureSettings {
        let app: AppSettings
        let shortcuts: ShortcutSettings
        let templateSettings: TemplateSettings

        var templates: [Template] { templateSettings.templates }
        var activeTemplateID: UUID { templateSettings.activeTemplateID }

        func setShortcut(_ combo: KeyCombo, for slot: ShortcutSlot) throws {
            try shortcuts.setShortcut(combo, for: slot)
        }
    }
    private let firstStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testDisabledCopyTitleExplainsStoreStatus() {
        withSettings { settings in
            let loading = items(facts: nil, status: .loading, settings: settings)
            let loadingCopy = entry(titled: "Loading notes…", in: loading)
            XCTAssertNotNil(loadingCopy)
            XCTAssertNil(loadingCopy?.action)

            let empty = facts(stacks: [Stack(id: firstStackID)], current: firstStackID)
            let available = items(facts: empty, status: .available, settings: settings)
            let emptyCopy = entry(titled: "Nothing captured yet", in: available)
            XCTAssertNotNil(emptyCopy)
            XCTAssertNil(emptyCopy?.action)

            let unavailable = items(facts: nil, status: .unavailable("disk full"), settings: settings)
            let unavailableCopy = entry(titled: "Notes unavailable: disk full", in: unavailable)
            XCTAssertNotNil(unavailableCopy)
            XCTAssertNil(unavailableCopy?.action)
            XCTAssertNil(entry(titled: "Stack 1 — Empty", in: unavailable), "no stacks to list without facts")
        }
    }

    func testTemplateSubmenuChecksActiveTemplateAndCarriesSelection() {
        withSettings { settings in
            let menu = items(facts: nil, status: .loading, settings: settings)
            guard let templates = submenu(titled: "Template", in: menu) else {
                return XCTFail("expected a Template submenu")
            }

            XCTAssertEqual(entries(in: templates).map(\.title), settings.templates.map(\.name))
            for template in settings.templates {
                let templateEntry = entry(titled: template.name, in: templates)
                XCTAssertEqual(templateEntry?.action, .selectTemplate(template.id))
                XCTAssertEqual(templateEntry?.checked, template.id == settings.activeTemplateID)
            }
            XCTAssertEqual(entries(in: templates).filter(\.checked).count, 1)
        }
    }

    func testEveryStackIsListedInlineWithItsCountShortcutAndSelectAction() throws {
        try withSettings { settings in
            let first = stack(id: firstStackID, noteCount: 1)
            let second = stack(id: secondStackID, noteCount: 2)
            let menu = items(
                facts: facts(stacks: [first, second], current: secondStackID),
                status: .available,
                settings: settings
            )

            let rows = entries(in: menu).filter {
                if case .selectStack = $0.action { return true }
                return false
            }
            XCTAssertEqual(rows.map(\.title), [
                "Stack 1 — 1 note", "Stack 2 — 2 notes", "Stack 3 — Empty", "Stack 4 — Empty", "Stack 5 — Empty",
            ])
            XCTAssertEqual(rows.map(\.action), (1...5).map { .selectStack($0) })
            XCTAssertEqual(rows.map(\.checked), [false, true, false, false, false])
            XCTAssertEqual(rows.map(\.keyEquivalent), ["h", "j", "k", "l", ";"])
            XCTAssertTrue(rows.allSatisfy { $0.keyEquivalentModifiers == [.option] })

            settings.shortcuts.clearShortcut(for: .selectStack(1))
            let unbound = items(
                facts: facts(stacks: [first, second], current: secondStackID),
                status: .available,
                settings: settings
            )
            XCTAssertNil(entry(titled: "Stack 1 — 1 note", in: unbound)?.keyEquivalent)
        }
    }

    func testMenuBarTitleIsTheStackNumberThenItsCount() {
        let stacks = facts(
            stacks: [stack(id: firstStackID, noteCount: 0), stack(id: secondStackID, noteCount: 4)],
            current: secondStackID
        )
        XCTAssertEqual(StatusMenuModel.title(for: stacks.current), " 2 · 4")
        XCTAssertEqual(StatusMenuModel.title(for: stacks.stack(number: 1)), " 1")
        XCTAssertEqual(StatusMenuModel.title(for: nil), "")
    }

    func testUndoItemAppearsOnlyWithAClearedBatch() {
        withSettings { settings in
            let stack = stack(id: firstStackID, noteCount: 1)
            let withoutUndo = facts(stacks: [stack], current: firstStackID)
            XCTAssertNil(entry(
                titled: "Undo Clear (1)",
                in: items(facts: withoutUndo, status: .available, settings: settings)
            ))

            let cleared = ClearedBatch(stackID: firstStackID, notes: [makeNote()])
            let withUndo = facts(stacks: [stack], current: firstStackID, lastCleared: cleared)
            let undo = entry(titled: "Undo Clear (1)", in: items(facts: withUndo, status: .available, settings: settings))
            XCTAssertEqual(undo?.action, .undoClear)
            XCTAssertEqual(undo?.keyEquivalent, "z")
        }
    }

    func testErrorAndRetryItemsRequireErrorAndPendingMutations() {
        withSettings { settings in
            let stack = stack(id: firstStackID, noteCount: 1)
            let current = facts(stacks: [stack], current: firstStackID)
            let noError = items(facts: current, status: .available, settings: settings)
            XCTAssertNil(entry(titled: "Couldn't save the stack change: disk full", in: noError))
            XCTAssertNil(entry(titled: "Retry Pending Stack Changes", in: noError))

            let error: StackStoreError = .commitFailed("disk full")
            let errorOnly = items(facts: current, status: .available, settings: settings, error: error)
            XCTAssertNotNil(entry(titled: "Couldn't save the stack change: disk full", in: errorOnly))
            XCTAssertNil(entry(titled: "Retry Pending Stack Changes", in: errorOnly))

            let pending = items(
                facts: current,
                status: .available,
                settings: settings,
                error: error,
                hasPendingMutations: true
            )
            XCTAssertEqual(entry(titled: "Couldn't save the stack change: disk full", in: pending)?.action, nil)
            XCTAssertEqual(
                entry(titled: "Retry Pending Stack Changes", in: pending)?.action,
                .retryPendingMutations
            )
        }
    }

    func testUpdateCheckIsAvailableFromTheStatusMenu() {
        withSettings { settings in
            let menu = items(facts: nil, status: .loading, settings: settings)
            XCTAssertEqual(entry(titled: "Check for Updates…", in: menu)?.action, .checkForUpdates)
        }
    }

    func testSettingsHiddenUntilSetupCompletes() {
        withSettings { settings in
            XCTAssertNil(entry(
                titled: "Settings…",
                in: items(facts: nil, status: .loading, settings: settings)
            ))
            settings.app.completeSetup()
            XCTAssertEqual(
                entry(
                    titled: "Settings…",
                    in: items(facts: nil, status: .loading, settings: settings)
                )?.action,
                .settings
            )
        }
    }

    private func items(
        facts: StackUIFacts?,
        status: StatusMenuStoreStatus,
        settings: FixtureSettings,
        error: StackStoreError? = nil,
        hasPendingMutations: Bool = false
    ) -> [StatusMenuItem] {
        StatusMenuModel.items(
            facts: facts,
            storeStatus: status,
            error: error,
            hasPendingMutations: hasPendingMutations,
            settings: settings.app,
            shortcuts: settings.shortcuts,
            templates: settings.templateSettings
        )
    }

    private func facts(stacks: [Stack], current: UUID, lastCleared: ClearedBatch? = nil) -> StackUIFacts {
        StackUIFacts(stacks: filled(stacks), currentStackID: current, lastCleared: lastCleared)
    }

    private func stack(id: UUID, noteCount: Int) -> Stack {
        Stack(id: id, notes: (0..<noteCount).map { _ in makeNote() })
    }

    private func makeNote() -> Note {
        Note(
            subject: .standalone,
            body: "A note"
        )
    }

    private func submenu(titled title: String, in items: [StatusMenuItem]) -> [StatusMenuItem]? {
        for item in items {
            if case let .submenu(itemTitle, contents) = item, itemTitle == title {
                return contents
            }
        }
        return nil
    }

    private func entry(titled title: String, in items: [StatusMenuItem]) -> StatusMenuEntry? {
        for item in items {
            if case let .entry(entry) = item, entry.title == title {
                return entry
            }
        }
        return nil
    }

    private func entries(in items: [StatusMenuItem]) -> [StatusMenuEntry] {
        items.compactMap {
            guard case let .entry(entry) = $0 else { return nil }
            return entry
        }
    }

    private func withSettings(_ body: (FixtureSettings) throws -> Void) rethrows {
        let suite = "StatusMenuModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(FixtureSettings(
            app: AppSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults),
            templateSettings: TemplateSettings(defaults: defaults)
        ))
    }
}
