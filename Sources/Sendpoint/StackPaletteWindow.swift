import AppKit
import Carbon.HIToolbox
import SendpointDomain
import SwiftUI

/// Owns the palette panel, its key handling, and its one teardown path.
final class StackPaletteWindowController: NSObject, NSWindowDelegate {
    private enum Lifecycle {
        case active
        case tornDown
    }

    private static let frameAutosaveName = "StackPalette"

    private let panel: CapturePanel
    private let model: StackPaletteModel
    private let surfaces: SurfaceCoordinator
    private var keyMonitor: Any?
    private var lifecycle: Lifecycle = .active

    init(
        store: StackStore,
        settings: AppSettings,
        export: ExportController,
        surfaces: SurfaceCoordinator,
        onSelectTemplate: @escaping (UUID) -> Void
    ) {
        self.surfaces = surfaces
        // Borderless: the SwiftUI sheet draws its own rounded edge, and the
        // window is clear behind it so the shadow follows that shape.
        let panel = Self.makePanel()
        self.panel = panel

        let model = StackPaletteModel(
            store: store, settings: settings, export: export, onSelectTemplate: onSelectTemplate
        )
        self.model = model
        super.init()
        model.onClose = { [weak surfaces] in surfaces?.dismiss(.palette) }
        panel.onClose = { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: StackPaletteView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        installKeyMonitor()
        surfaces.register(.palette, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide() }
        ))
    }

    static func makePanel() -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Stacks"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = StackPaletteView.minimumSize
        return panel
    }

    func show(at level: PaletteLevel, highlighting stackID: UUID? = nil) {
        guard lifecycle == .active else { return }
        model.send(.open(level))
        if let stackID, level == .stacks { model.send(.chooseStack(stackID)) }
        surfaces.present(.palette)
    }

    private func present() {
        if !panel.isVisible {
            if !panel.setFrameUsingName(Self.frameAutosaveName) {
                placeNearTop()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// The only close path. Safe to call more than once.
    func close() { model.send(.close) }

    func teardown() {
        guard lifecycle == .active else { return }
        model.send(.teardown)
        surfaces.unregister(.palette)
        releaseWindow()
    }

    func documentChanged() { model.send(.documentChanged) }

    private func hide() {
        guard lifecycle == .active else { return }
        model.send(.close)
        panel.saveFrame(usingName: Self.frameAutosaveName)
        panel.orderOut(nil)
    }

    private func releaseWindow() {
        guard lifecycle == .active else { return }
        lifecycle = .tornDown
        panel.saveFrame(usingName: Self.frameAutosaveName)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard lifecycle == .active else { return }
        surfaces.resignedKey(.palette)
    }

    // MARK: - Keys

    /// Every key the palette cares about is handled here, ahead of the text
    /// fields, so ↑↓ move the highlight instead of the insertion point. Any
    /// key the model declines falls through to the field.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.lifecycle == .active, event.window === self.panel,
                  let key = PaletteKey(event: event)
            else { return event }
            let selection = (self.panel.firstResponder as? NSTextView)?.selectedRange().length ?? 0
            let handled = self.model.send(.key(key, textHasSelection: selection > 0))
            return handled ? nil : event
        }
    }

    // MARK: - Placement

    private func placeNearTop() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - visible.height * 0.18 - size.height
            ))
    }
}

extension PaletteKey {
    private static let commandLetters: Set<Character> = ["c", "k", "n", "o", "p", "r", "z"]

    /// Decodes an event by character rather than hardware key code where a
    /// letter is involved, so ⌘R survives non-US keyboard layouts.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let plain = modifiers.isEmpty
        let command = modifiers == .command
        let shiftCommand = modifiers == [.command, .shift]
        let option = modifiers == .option
        let shift = modifiers == .shift
        switch event.keyCode {
        case UInt16(kVK_UpArrow) where plain: self = .up
        case UInt16(kVK_DownArrow) where plain: self = .down
        case UInt16(kVK_LeftArrow) where plain: self = .left
        case UInt16(kVK_RightArrow) where plain: self = .right
        case UInt16(kVK_UpArrow) where option: self = .optionUp
        case UInt16(kVK_DownArrow) where option: self = .optionDown
        case UInt16(kVK_Tab) where plain: self = .tab
        case UInt16(kVK_Tab) where shift: self = .backTab
        case UInt16(kVK_Return) where plain, UInt16(kVK_ANSI_KeypadEnter) where plain:
            self = .activate
        case UInt16(kVK_Return) where command, UInt16(kVK_ANSI_KeypadEnter) where command:
            self = .commandActivate
        case UInt16(kVK_Escape) where plain: self = .escape
        case UInt16(kVK_Delete) where plain: self = .delete
        case UInt16(kVK_Delete) where command: self = .commandDelete
        case UInt16(kVK_Delete) where shiftCommand: self = .shiftCommandDelete
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first else {
                return nil
            }
            if command, let digit = character.wholeNumberValue, (1...9).contains(digit) {
                self = .commandDigit(digit)
            } else if command, Self.commandLetters.contains(character) {
                self = .command(character)
            } else if shiftCommand, character == "c" {
                self = .shiftCommand(character)
            } else {
                return nil
            }
        }
    }
}
