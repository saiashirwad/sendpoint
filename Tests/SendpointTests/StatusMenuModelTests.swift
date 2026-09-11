import AppKit
import Carbon.HIToolbox
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StatusMenuModelTests: XCTestCase {
    private let firstStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private let secondStackID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    func testDisabledCopyTitleExplainsStoreStatus() {
        withSettings { settings in
            let loading = items(facts: nil, status: .loading, settings: settings)
            let loadingCopy = entry(titled: "Loading notes…", in: loading)
            XCTAssertNotNil(loadingCopy)
            XCTAssertNil(loadingCopy?.action)

            let empty = facts(sessions: [Session(id: firstStackID, name: "Default")], current: firstStackID)
            let available = items(facts: empty, status: .available, settings: settings)
            let emptyCopy = entry(titled: "Nothing captured yet", in: available)
            XCTAssertNotNil(emptyCopy)
            XCTAssertNil(emptyCopy?.action)

            let unavailable = items(facts: nil, status: .unavailable("disk full"), settings: settings)
            let unavailableCopy = entry(titled: "Notes unavailable: disk full", in: unavailable)
            XCTAssertNotNil(unavailableCopy)
            XCTAssertNil(unavailableCopy?.action)
        }
    }

    func testCopyItemUsesExportVerbAndPluralizesNotes() {
        withSettings { settings in
            settings.pasteDirectly = false

            let one = facts(sessions: [session(id: firstStackID, name: "First", noteCount: 1)], current: firstStackID)
            let oneCopy = entry(titled: "Copy 1 Note as Markdown", in: items(facts: one, status: .available, settings: settings))
            XCTAssertEqual(oneCopy?.action, .copyMarkdown)

            let two = facts(sessions: [session(id: firstStackID, name: "First", noteCount: 2)], current: firstStackID)
            let twoCopy = entry(titled: "Copy 2 Notes as Markdown", in: items(facts: two, status: .available, settings: settings))
            XCTAssertEqual(twoCopy?.action, .copyMarkdown)
        }
    }

    func testProfileSubmenuChecksActiveProfileAndCarriesSelection() {
        withSettings { settings in
            let menu = items(facts: nil, status: .loading, settings: settings)
            guard let profiles = submenu(titled: "Template", in: menu) else {
                return XCTFail("expected a Template submenu")
            }

            XCTAssertEqual(entries(in: profiles).map(\.title), settings.profiles.map(\.name))
            for profile in settings.profiles {
                let profileEntry = entry(titled: profile.name, in: profiles)
                XCTAssertEqual(profileEntry?.action, .selectProfile(profile.id))
                XCTAssertEqual(profileEntry?.representedID, profile.id)
                XCTAssertEqual(profileEntry?.checked, profile.id == settings.activeProfileID)
            }
            XCTAssertEqual(entries(in: profiles).filter(\.checked).count, 1)
        }
    }

    func testStackSubmenuListsSessionsWithCountsAndSwitchActions() {
        withSettings { settings in
            let first = session(id: firstStackID, name: "First", noteCount: 1)
            let second = session(id: secondStackID, name: "Second", noteCount: 2)
            let menu = items(
                facts: facts(sessions: [first, second], current: firstStackID),
                status: .available,
                settings: settings
            )

            guard let stack = submenu(titled: "Stack", in: menu) else {
                return XCTFail("expected a Stack submenu")
            }
            let rows = Array(entries(in: stack).prefix(2))
            XCTAssertEqual(rows.map(\.title), ["First — 1 note", "Second — 2 notes"])
            XCTAssertEqual(rows.map(\.action), [.switchToStack(firstStackID), .switchToStack(secondStackID)])
            XCTAssertEqual(rows.map(\.representedID), [firstStackID, secondStackID])
            XCTAssertEqual(rows.map(\.checked), [true, false])
            XCTAssertEqual(entry(titled: "Switch Stack…", in: stack)?.action, .quickSwitcher)
        }
    }

    func testStackSubmenuIsAbsentWithoutFacts() {
        withSettings { settings in
            let menu = items(facts: nil, status: .unavailable("gone"), settings: settings)
            XCTAssertNil(submenu(titled: "Stack", in: menu))
        }
    }

    func testUndoItemAppearsOnlyWithAClearedBatch() {
        withSettings { settings in
            let session = session(id: firstStackID, name: "First", noteCount: 1)
            let withoutUndo = facts(sessions: [session], current: firstStackID)
            XCTAssertNil(entry(
                titled: "Undo Clear (1)",
                in: items(facts: withoutUndo, status: .available, settings: settings)
            ))

            let cleared = ClearedBatch(sessionID: firstStackID, entries: [annotation()])
            let withUndo = facts(sessions: [session], current: firstStackID, lastCleared: cleared)
            let undo = entry(titled: "Undo Clear (1)", in: items(facts: withUndo, status: .available, settings: settings))
            XCTAssertEqual(undo?.action, .undoClear)
            XCTAssertEqual(undo?.keyEquivalent, "z")
        }
    }

    func testErrorAndRetryItemsRequireErrorAndPendingMutations() {
        withSettings { settings in
            let session = session(id: firstStackID, name: "First", noteCount: 1)
            let current = facts(sessions: [session], current: firstStackID)
            let noError = items(facts: current, status: .available, settings: settings)
            XCTAssertNil(entry(titled: "Couldn't save the stack change: disk full", in: noError))
            XCTAssertNil(entry(titled: "Retry Pending Stack Changes", in: noError))

            let error: AnnotationStoreError = .commitFailed("disk full")
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

    func testNextAndPreviousStackAppearOnlyWhenTheirCombosAreSet() throws {
        try withSettings { settings in
            let current = facts(sessions: [session(id: firstStackID, name: "First", noteCount: 1)], current: firstStackID)
            let unbound = submenu(titled: "Stack", in: items(facts: current, status: .available, settings: settings))
            XCTAssertNotNil(unbound)
            XCTAssertNil(entry(titled: "Next Stack", in: unbound ?? []))
            XCTAssertNil(entry(titled: "Previous Stack", in: unbound ?? []))

            let next = KeyCombo(keyCode: UInt16(kVK_ANSI_N), modifiers: [.control, .option])
            let previous = KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .option])
            try settings.setShortcut(next, for: .nextStack)
            try settings.setShortcut(previous, for: .previousStack)

            let bound = submenu(titled: "Stack", in: items(facts: current, status: .available, settings: settings))
            let nextEntry = entry(titled: "Next Stack", in: bound ?? [])
            let previousEntry = entry(titled: "Previous Stack", in: bound ?? [])
            XCTAssertEqual(nextEntry?.action, .nextStack)
            XCTAssertEqual(nextEntry?.keyEquivalent, "n")
            XCTAssertEqual(nextEntry?.keyEquivalentModifiers, [.control, .option])
            XCTAssertEqual(previousEntry?.action, .previousStack)
            XCTAssertEqual(previousEntry?.keyEquivalent, "p")
            XCTAssertEqual(previousEntry?.keyEquivalentModifiers, [.control, .option])
        }
    }

    func testTopLevelOrderAndChromeMatchTheDelegateMenu() {
        withSettings { settings in
            let session = session(id: firstStackID, name: "First", noteCount: 1)
            let cleared = ClearedBatch(sessionID: firstStackID, entries: [annotation()])
            let menu = items(
                facts: facts(sessions: [session], current: firstStackID, lastCleared: cleared),
                status: .available,
                settings: settings,
                error: .mutationRejected("nope"),
                hasPendingMutations: true
            )

            XCTAssertEqual(topLevelTitles(menu), [
                "Voice Note (\(settings.voiceCaptureCombo.displayString))",
                "Typed Note",
                "Show Stack…",
                "First — 1 note",
                "Stack",
                "Template",
                "Paste 1 Note as Markdown",
                "Clear First",
                "Undo Clear (1)",
                "nope",
                "Retry Pending Stack Changes",
                "Settings…",
                "Quit Sendpoint",
            ])

            let voice = entry(titled: "Voice Note (\(settings.voiceCaptureCombo.displayString))", in: menu)
            XCTAssertNil(voice?.keyEquivalent)
            XCTAssertEqual(voice?.tooltip, settings.voiceCaptureCombo.displayString)

            let typed = entry(titled: "Typed Note", in: menu)
            XCTAssertEqual(typed?.keyEquivalent, settings.captureCombo.menuKeyEquivalent)
            XCTAssertEqual(typed?.keyEquivalentModifiers, settings.captureCombo.modifiers)

            XCTAssertEqual(entry(titled: "Settings…", in: menu)?.keyEquivalent, ",")
            XCTAssertEqual(entry(titled: "Quit Sendpoint", in: menu)?.keyEquivalent, "q")
            XCTAssertEqual(menu.filter { $0 == .separator }.count, 3)
        }
    }

    private func items(
        facts: SessionUIFacts?,
        status: StatusMenuStoreStatus,
        settings: AppSettings,
        error: AnnotationStoreError? = nil,
        hasPendingMutations: Bool = false
    ) -> [StatusMenuItem] {
        StatusMenuModel.items(
            facts: facts,
            storeStatus: status,
            error: error,
            hasPendingMutations: hasPendingMutations,
            settings: settings
        )
    }

    private func facts(sessions: [Session], current: UUID, lastCleared: ClearedBatch? = nil) -> SessionUIFacts {
        SessionUIFacts(sessions: sessions, currentSessionID: current, lastCleared: lastCleared)
    }

    private func session(id: UUID, name: String, noteCount: Int) -> Session {
        Session(id: id, name: name, entries: (0..<noteCount).map { _ in annotation() })
    }

    private func annotation() -> Annotation {
        Annotation(
            subject: .standalone,
            note: "A note",
            provenance: Provenance(application: ApplicationIdentity(name: "Safari"))
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

    private func topLevelTitles(_ items: [StatusMenuItem]) -> [String] {
        items.compactMap {
            switch $0 {
            case let .entry(entry): entry.title
            case .separator: nil
            case let .submenu(title, _): title
            }
        }
    }

    private func withSettings(_ body: (AppSettings) throws -> Void) rethrows {
        let suite = "StatusMenuModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults))
    }
}
