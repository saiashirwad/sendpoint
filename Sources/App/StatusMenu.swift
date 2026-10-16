import AppKit
import Core

/// Menu bar item: shows the active stack, switches stacks, pastes, quits.
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var shown = ""

    func render(_ w: World, speechStatus: String) {
        let count = w.stacks[w.active].count
        // Typing re-renders on every keystroke; rebuild only when what's shown changes.
        let key = "\(w.stacks.map(\.count)) \(w.active) \(w.mode == .idle) \(AXIsProcessTrusted()) \(speechStatus)"
        guard key != shown else { return }
        shown = key
        item.button?.title = "✎ \(w.active + 1)" + (count > 0 ? "·\(count)" : "")

        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, notes) in w.stacks.enumerated() {
            let row = NSMenuItem(title: "Stack \(i + 1) — \(notes.count) note\(notes.count == 1 ? "" : "s")",
                                 action: #selector(select(_:)), keyEquivalent: "")
            row.tag = i
            row.target = self
            row.state = i == w.active ? .on : .off
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let paste = NSMenuItem(title: "Paste Stack \(w.active + 1)  ⌃⌘V", action: #selector(paste), keyEquivalent: "")
        paste.target = self
        paste.isEnabled = count > 0 && w.mode == .idle
        menu.addItem(paste)
        if !AXIsProcessTrusted() {
            menu.addItem(action("Grant Accessibility…", #selector(openAccessibility)))
        }
        if !speechStatus.isEmpty {
            let status = NSMenuItem(title: speechStatus, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sendpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func select(_ sender: NSMenuItem) { send(.select(sender.tag)) }
    @objc private func paste() { send(.paste) }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
