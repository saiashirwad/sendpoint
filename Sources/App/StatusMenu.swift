import AppKit
import Core

/// Menu bar item: shows the active stack, switches stacks, opens and pastes, edits the config.
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var shown = ""

    func render(_ w: World) {
        let count = w.stacks[w.active].count
        // Typing re-renders on every keystroke; rebuild only when what's shown changes.
        let key = "\(w.stacks.map(\.count)) \(w.active) \(w.mode == .idle) \(AXIsProcessTrusted()) \(w.voice) \(w.config) \(Keys.problems)"
        guard key != shown else { return }
        shown = key
        item.button?.title = "✎ \(w.active + 1)" + (count > 0 ? "·\(count)" : "")

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, notes) in w.stacks.enumerated() {
            let row = action("\(w.config.names[i]) — \(notes.count) note\(notes.count == 1 ? "" : "s")",
                             #selector(select(_:)), w.config.keys[Action.stack1.rawValue + i])
            row.tag = i
            row.state = i == w.active ? .on : .off
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let name = w.config.names[w.active]
        menu.addItem(action("Open \(name)", #selector(open), w.config.keys[Action.open.rawValue]))
        let paste = action("Paste \(name)", #selector(paste), w.config.keys[Action.paste.rawValue])
        paste.isEnabled = count > 0 && w.mode == .idle
        menu.addItem(paste)

        menu.addItem(.separator())
        let config = NSMenuItem(title: "Edit Config…", action: #selector(editConfig), keyEquivalent: ",")
        config.target = self
        menu.addItem(config)
        for problem in w.config.problems + Keys.problems {
            menu.addItem(note("⚠︎ " + problem))
        }
        if !AXIsProcessTrusted() {
            menu.addItem(action("Grant Accessibility…", #selector(openAccessibility), nil))
        }
        if !w.voice.label.isEmpty { menu.addItem(note(w.voice.label)) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sendpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    /// Shows the global shortcut beside the item when it's a plain character key.
    private func action(_ title: String, _ selector: Selector, _ shortcut: Shortcut?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        if let shortcut, let k = keyCodes.firstIndex(of: shortcut.code), keyNames[k].count == 1 {
            item.keyEquivalent = keyNames[k]
            var mask: NSEvent.ModifierFlags = []
            if shortcut.mods & modCmd != 0 { mask.insert(.command) }
            if shortcut.mods & modOpt != 0 { mask.insert(.option) }
            if shortcut.mods & modCtrl != 0 { mask.insert(.control) }
            if shortcut.mods & modShift != 0 { mask.insert(.shift) }
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    private func note(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func select(_ sender: NSMenuItem) { send(.select(sender.tag)) }
    @objc private func open() { send(.open) }
    @objc private func paste() { send(.paste) }
    @objc private func editConfig() { openFile(configURL) }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
