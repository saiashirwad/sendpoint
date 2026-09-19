import AppKit
import SendpointDomain

enum StatusMenuAction: Hashable {
    case voiceNote
    case typedNote
    case dictate
    case showStack
    case selectStack(Int)
    case selectTemplate(UUID)
    case copyMarkdown
    case clearStack(UUID)
    case undoClear
    case retryPendingMutations
    case checkForUpdates
    case settings
    case quit
}

struct StatusMenuEntry: Equatable {
    var title: String
    var action: StatusMenuAction?
    var checked: Bool
    var keyEquivalent: String?
    var keyEquivalentModifiers: NSEvent.ModifierFlags?
    var tooltip: String?

    init(
        title: String,
        action: StatusMenuAction? = nil,
        checked: Bool = false,
        keyEquivalent: String? = nil,
        keyEquivalentModifiers: NSEvent.ModifierFlags? = nil,
        tooltip: String? = nil
    ) {
        self.title = title
        self.action = action
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

enum StatusMenuModel {
    static func items(
        facts: StackUIFacts?,
        storeStatus: StatusMenuStoreStatus,
        error: StackStoreError?,
        hasPendingMutations: Bool,
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        templates: TemplateSettings
    ) -> [StatusMenuItem] {
        let ready = storeStatus == .available
        var menu: [StatusMenuItem] = []

        menu.append(.entry(StatusMenuEntry(
            title: "Voice Note (\(shortcuts.voiceCaptureCombo.displayString))",
            action: ready ? .voiceNote : nil,
            tooltip: shortcuts.voiceCaptureCombo.displayString
        )))
        menu.append(.entry(entry("Typed Note",
            action: ready ? .typedNote : nil,
            combo: shortcuts.captureCombo)))
        if let combo = shortcuts.dictateCombo {
            menu.append(.entry(entry("Dictate",
                action: ready ? .dictate : nil,
                combo: combo)))
        }
        menu.append(.entry(entry("Show Stack…",
            action: ready ? .showStack : nil,
            combo: shortcuts.stackCombo)))

        if let facts, facts.current != nil {
            menu.append(.separator)
            for stack in facts.stacks {
                menu.append(.entry(entry("\(stack.name) — \(stack.isEmpty ? "Empty" : stack.countLabel)",
                    action: .selectStack(stack.number),
                    checked: stack.isCurrent,
                    combo: shortcuts.selectStackCombo(stack.number))))
            }
            menu.append(.separator)
        }

        var templateMenu: [StatusMenuItem] = []
        for template in templates.templates {
            templateMenu.append(.entry(entry(template.name,
                action: .selectTemplate(template.id),
                checked: template.id == templates.activeTemplateID)))
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
            combo: shortcuts.copyCombo)))
        var clear = entry(
            facts?.current.map { "Clear \($0.name)" } ?? "Clear Current Stack",
            combo: shortcuts.clearCombo)
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
            title: "Check for Updates…",
            action: .checkForUpdates)))
        if settings.hasCompletedSetup {
            menu.append(.entry(StatusMenuEntry(
                title: "Settings…",
                action: .settings,
                keyEquivalent: ",")))
        }
        menu.append(.entry(StatusMenuEntry(
            title: "Quit Sendpoint",
            action: .quit,
            keyEquivalent: "q")))

        return menu
    }

    static func title(for current: StackItemFacts?) -> String {
        guard let current else { return "" }
        return current.isEmpty ? " \(current.number)" : " \(current.number) · \(current.noteCount)"
    }

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

    private static func entry(
        _ title: String,
        action: StatusMenuAction? = nil,
        checked: Bool = false,
        combo: KeyCombo? = nil
    ) -> StatusMenuEntry {
        var entry = StatusMenuEntry(title: title, action: action, checked: checked)
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
