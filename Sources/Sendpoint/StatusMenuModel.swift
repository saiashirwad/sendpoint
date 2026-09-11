import AppKit
import SendpointDomain

/// One command the status menu can invoke. The associated value, when there is
/// one, identifies the stack or template the command applies to.
enum StatusMenuAction: Hashable {
    case voiceNote
    case typedNote
    case showStack
    case switchToStack(UUID)
    case quickSwitcher
    case nextStack
    case previousStack
    case selectTemplate(UUID)
    case copyMarkdown
    case clearStack(UUID)
    case undoClear
    case retryPendingMutations
    case settings
    case quit
}

/// One rendered menu item, still free of `NSMenuItem`. A nil action is a
/// disabled item; a nil `keyEquivalentModifiers` leaves the item's default
/// modifier mask alone.
struct StatusMenuEntry: Equatable {
    var title: String
    var action: StatusMenuAction?
    var representedID: UUID?
    var checked: Bool
    var keyEquivalent: String?
    var keyEquivalentModifiers: NSEvent.ModifierFlags?
    var tooltip: String?

    init(
        title: String,
        action: StatusMenuAction? = nil,
        representedID: UUID? = nil,
        checked: Bool = false,
        keyEquivalent: String? = nil,
        keyEquivalentModifiers: NSEvent.ModifierFlags? = nil,
        tooltip: String? = nil
    ) {
        self.title = title
        self.action = action
        self.representedID = representedID
        self.checked = checked
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifiers = keyEquivalentModifiers
        self.tooltip = tooltip
    }
}

enum StatusMenuItem: Equatable {
    case entry(StatusMenuEntry)
    case separator
    case submenu(title: String, items: [StatusMenuItem])
}

enum StatusMenuStoreStatus: Equatable {
    case loading
    case available
    case unavailable(String)
}

/// Builds the status menu as plain values. `AppDelegate` only supplies the
/// current store and settings facts, so the menu stays testable without AppKit.
enum StatusMenuModel {
    static func items(
        facts: StackUIFacts?,
        storeStatus: StatusMenuStoreStatus,
        error: StackStoreError?,
        hasPendingMutations: Bool,
        settings: AppSettings
    ) -> [StatusMenuItem] {
        let ready = storeStatus == .available
        var menu: [StatusMenuItem] = []

        menu.append(.entry(StatusMenuEntry(
            title: "Voice Note (\(settings.voiceCaptureCombo.displayString))",
            action: ready ? .voiceNote : nil,
            tooltip: settings.voiceCaptureCombo.displayString
        )))
        menu.append(.entry(entry("Typed Note",
            action: ready ? .typedNote : nil,
            combo: settings.captureCombo)))
        menu.append(.entry(entry("Show Stack…",
            action: ready ? .showStack : nil,
            combo: settings.stackCombo)))

        if let facts, facts.current != nil {
            menu.append(.entry(entry(facts.currentTitle)))
            var stackMenu: [StatusMenuItem] = []
            for stack in facts.stacks {
                stackMenu.append(.entry(entry("\(stack.name) — \(stack.countLabel)",
                    action: .switchToStack(stack.id),
                    represents: stack.id,
                    checked: stack.isCurrent)))
            }
            stackMenu.append(.separator)
            stackMenu.append(.entry(entry("Switch Stack…",
                action: .quickSwitcher,
                combo: settings.switchStackCombo)))
            if let combo = settings.nextStackCombo {
                stackMenu.append(.entry(entry("Next Stack",
                    action: .nextStack,
                    combo: combo)))
            }
            if let combo = settings.previousStackCombo {
                stackMenu.append(.entry(entry("Previous Stack",
                    action: .previousStack,
                    combo: combo)))
            }
            menu.append(.submenu(title: "Stack", items: stackMenu))
        }

        var templateMenu: [StatusMenuItem] = []
        for template in settings.templates {
            templateMenu.append(.entry(entry(template.name,
                action: .selectTemplate(template.id),
                represents: template.id,
                checked: template.id == settings.activeTemplateID)))
        }
        menu.append(.submenu(title: "Template", items: templateMenu))
        menu.append(.separator)

        let count = facts?.current?.noteCount ?? 0
        let verb = settings.pasteDirectly ? "Paste" : "Copy"
        menu.append(.entry(entry(
            count > 0
                ? "\(verb) \(count) Note\(count == 1 ? "" : "s") as Markdown"
                : unavailableTitle(for: storeStatus),
            action: count > 0 ? .copyMarkdown : nil,
            combo: settings.copyCombo)))
        var clear = entry(
            facts?.current.map { "Clear \($0.name)" } ?? "Clear Current Stack",
            represents: facts?.current?.id,
            combo: settings.clearCombo)
        if count > 0, let stackID = facts?.current?.id {
            clear.action = .clearStack(stackID)
        }
        menu.append(.entry(clear))
        if let undo = facts?.undo {
            menu.append(.entry(StatusMenuEntry(
                title: undo.title,
                action: .undoClear,
                keyEquivalent: "z")))
        }

        if let error {
            menu.append(.separator)
            menu.append(.entry(entry(noteStoreErrorMessage(error))))
            if hasPendingMutations {
                menu.append(.entry(entry("Retry Pending Stack Changes",
                    action: .retryPendingMutations)))
            }
        }

        menu.append(.separator)
        menu.append(.entry(StatusMenuEntry(
            title: "Settings…",
            action: .settings,
            keyEquivalent: ",")))
        menu.append(.entry(StatusMenuEntry(
            title: "Quit Sendpoint",
            action: .quit,
            keyEquivalent: "q")))

        return menu
    }

    /// The disabled copy item explains why there is nothing to export yet.
    private static func unavailableTitle(for status: StatusMenuStoreStatus) -> String {
        switch status {
        case .loading:
            "Loading notes…"
        case .available:
            "Nothing captured yet"
        case let .unavailable(message):
            "Notes unavailable: \(message)"
        }
    }

    /// Mirrors menu-item construction for one command: a valid global shortcut
    /// is shown beside the item, and otherwise its display string becomes the
    /// tooltip.
    private static func entry(
        _ title: String,
        action: StatusMenuAction? = nil,
        represents id: UUID? = nil,
        checked: Bool = false,
        combo: KeyCombo? = nil
    ) -> StatusMenuEntry {
        var entry = StatusMenuEntry(
            title: title,
            action: action,
            representedID: id,
            checked: checked
        )
        if let combo, combo.isValid {
            if let equivalent = combo.menuKeyEquivalent {
                entry.keyEquivalent = equivalent
                entry.keyEquivalentModifiers = combo.modifiers
            } else {
                entry.tooltip = combo.displayString
            }
        }
        return entry
    }
}
