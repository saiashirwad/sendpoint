import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let shortcuts: ShortcutSettings
    private let templates: TemplateSettings
    private let voiceSettings: VoiceSettings
    private let hotKeyRegistrar: HotKeyRegistrar
    private let captureController: CaptureController
    private let permissionState: PermissionState
    private let surfaces: SurfaceCoordinator
    private let onSelectTemplate: (UUID) -> Void
    private let onShowAccessibilityHelper: () -> Void
    private let onSettingsChanged: () -> Void
    private var window: NSWindow?
    private(set) var templateEditor: TemplateEditorState?

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        templates: TemplateSettings,
        voiceSettings: VoiceSettings,
        hotKeyRegistrar: HotKeyRegistrar,
        captureController: CaptureController,
        permissionState: PermissionState,
        surfaces: SurfaceCoordinator,
        onSelectTemplate: @escaping (UUID) -> Void,
        onShowAccessibilityHelper: @escaping () -> Void,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.shortcuts = shortcuts
        self.templates = templates
        self.voiceSettings = voiceSettings
        self.hotKeyRegistrar = hotKeyRegistrar
        self.captureController = captureController
        self.permissionState = permissionState
        self.surfaces = surfaces
        self.onSelectTemplate = onSelectTemplate
        self.onShowAccessibilityHelper = onShowAccessibilityHelper
        self.onSettingsChanged = onSettingsChanged
        super.init()
        surfaces.register(.settings, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.window?.orderOut(nil) }
        ))
    }

    func show() {
        permissionState.refresh()
        surfaces.present(.settings)
    }

    func requestTemplateSelection(_ templateID: UUID) -> Bool {
        guard let templateEditor else { return false }
        switch templateEditor.requestSelection(templateID) {
        case .needsDecision:
            _ = TemplateDialogs.resolvePendingSelection(templateEditor)
        case .selected, .unchanged:
            break
        case .rejected:
            NSSound.beep()
        }
        return true
    }

    func canTerminate() -> Bool {
        guard let templateEditor else { return true }
        return TemplateDialogs.shouldClose(templateEditor)
    }

    func teardown() {
        surfaces.unregister(.settings)
        window?.delegate = nil
        window?.close()
        window = nil
        templateEditor = nil
    }

    private func present() {
        let window = self.window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindowFrame()
        let templateEditor = TemplateEditorState(settings: templates, onChange: onSettingsChanged)
        self.templateEditor = templateEditor
        let settingsView = SettingsView(
            settings: settings,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            hotKeyRegistrar: hotKeyRegistrar,
            captureController: captureController,
            templateEditor: templateEditor,
            permissionState: permissionState,
            onSelectTemplate: onSelectTemplate,
            onShowAccessibilityHelper: onShowAccessibilityHelper,
            onSettingsChanged: onSettingsChanged
        )
        let hosting = NSHostingView(rootView: settingsView)
        hosting.safeAreaRegions = []
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.delegate = self
        self.window = window
        return window
    }

    static func makeWindowFrame() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "SettingsWindowToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = SettingsView.size
        window.setContentSize(SettingsView.size)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === window else { return frameSize }
        let minimum = sender.frameRect(forContentRect: NSRect(origin: .zero, size: SettingsView.size)).size
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window, let templateEditor else { return true }
        return TemplateDialogs.shouldClose(templateEditor)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        surfaces.userClosed(.settings)
        window = nil
        templateEditor = nil
    }
}
