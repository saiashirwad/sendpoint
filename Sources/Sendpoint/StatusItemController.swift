import AppKit
import SendpointDomain

/// Owns the menu-bar status item: its glyph, its title and flash, and the
/// status menu rendered from `StatusMenuModel`.
@MainActor
final class StatusItemController {
    /// The action and the ID it was built from, kept together for the single
    /// menu-action entry point.
    private final class MenuActionBox {
        let action: StatusMenuAction
        let representedID: UUID?

        init(_ action: StatusMenuAction, representedID: UUID?) {
            self.action = action
            self.representedID = representedID
        }
    }

    private let statusItem: NSStatusItem
    private var baseTitle = ""
    private var baseTooltip = ""
    private var flashToken = 0
    private var isFlashing = false
    private var flashTask: Task<Void, Never>?

    var onAction: ((StatusMenuAction) -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.imagePosition = .imageLeading
        }
        statusItem.isVisible = true
        Diag.log("statusItem button=\(statusItem.button != nil) visible=\(statusItem.isVisible)")
    }

    func setBaseTitle(_ title: String, tooltip: String) {
        baseTitle = title
        baseTooltip = tooltip
        applyBaseTitle()
    }

    /// Shows `text` in place of the count for 1.4 seconds. A newer flash
    /// cancels the older one, and a stale restore never applies.
    func flash(_ text: String) {
        flashToken += 1
        let token = flashToken
        isFlashing = true
        statusItem.button?.title = " \(text)"
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            guard let self, self.flashToken == token else { return }
            self.isFlashing = false
            self.flashTask = nil
            self.applyBaseTitle()
        }
    }

    func rebuildMenu(
        facts: SessionUIFacts?,
        storeStatus: StatusMenuStoreStatus,
        error: AnnotationStoreError?,
        hasPendingMutations: Bool,
        settings: AppSettings
    ) {
        let menu = NSMenu()
        let items = StatusMenuModel.items(
            facts: facts,
            storeStatus: storeStatus,
            error: error,
            hasPendingMutations: hasPendingMutations,
            settings: settings
        )
        for item in items {
            menu.addItem(render(item))
        }
        statusItem.menu = menu
    }

    func teardown() {
        flashTask?.cancel()
        flashTask = nil
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// The count and tooltip are held back while a flash is showing, exactly
    /// as the delegate used to skip its title update.
    private func applyBaseTitle() {
        guard !isFlashing else { return }
        statusItem.button?.title = baseTitle
        statusItem.button?.toolTip = baseTooltip
    }

    private func render(_ item: StatusMenuItem) -> NSMenuItem {
        switch item {
        case let .entry(entry):
            return render(entry)
        case .separator:
            return .separator()
        case let .submenu(title, items):
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            root.target = self
            let submenu = NSMenu(title: title)
            for item in items {
                submenu.addItem(render(item))
            }
            root.submenu = submenu
            return root
        }
    }

    private func render(_ entry: StatusMenuEntry) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: entry.title,
            action: entry.action == nil ? nil : #selector(handleMenuAction(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        if let action = entry.action {
            menuItem.representedObject = MenuActionBox(action, representedID: entry.representedID)
        }
        menuItem.state = entry.checked ? .on : .off
        if let tooltip = entry.tooltip {
            menuItem.toolTip = tooltip
        }
        if let keyEquivalent = entry.keyEquivalent {
            menuItem.keyEquivalent = keyEquivalent
            if let modifiers = entry.keyEquivalentModifiers {
                menuItem.keyEquivalentModifierMask = modifiers
            }
        }
        return menuItem
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? MenuActionBox else { return }
        onAction?(box.action)
    }
}
