import AppKit
import SendpointDomain
import SwiftUI

@Observable
final class SettingsStoreHandle {
    var store: StackStore?
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let shortcuts: ShortcutSettings
    private let templates: TemplateSettings
    private let voiceSettings: VoiceSettings
    private let hotKeyRegistrar: HotKeyRegistrar
    private let captureController: CaptureController
    private let permissionState: PermissionController
    private let surfaces: SurfaceCoordinator
    private let storeHandle = SettingsStoreHandle()
    private let onSelectTemplate: (UUID) -> Void
    private let onSettingsChanged: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onShowStack: () -> Void
    private var window: NSWindow?
    private(set) var templateEditor: TemplateEditorController?

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        templates: TemplateSettings,
        voiceSettings: VoiceSettings,
        hotKeyRegistrar: HotKeyRegistrar,
        captureController: CaptureController,
        permissionState: PermissionController,
        surfaces: SurfaceCoordinator,
        stackStore: StackStore?,
        onSelectTemplate: @escaping (UUID) -> Void,
        onSettingsChanged: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onShowStack: @escaping () -> Void
    ) {
        self.settings = settings
        self.shortcuts = shortcuts
        self.templates = templates
        self.voiceSettings = voiceSettings
        self.hotKeyRegistrar = hotKeyRegistrar
        self.captureController = captureController
        self.permissionState = permissionState
        self.surfaces = surfaces
        storeHandle.store = stackStore
        self.onSelectTemplate = onSelectTemplate
        self.onSettingsChanged = onSettingsChanged
        self.onCheckForUpdates = onCheckForUpdates
        self.onShowStack = onShowStack
        super.init()
        surfaces.register(.settings, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide() }
        ))
    }

    func show() {
        permissionState.refresh()
        surfaces.present(.settings)
    }

    func storeDidBecomeAvailable(_ store: StackStore) {
        storeHandle.store = store
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
        permissionState.stopWatchingVoiceModel()
        window?.delegate = nil
        window?.close()
        window = nil
        templateEditor?.teardown()
        templateEditor = nil
    }

    private func present() {
        permissionState.startWatchingVoiceModel()
        let window = self.window ?? makeWindow()
        window.presentActivated()
        window.makeFirstResponder(nil)
    }

    private func hide() {
        permissionState.stopWatchingVoiceModel()
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindowFrame()
        let templateEditor = TemplateEditorController(settings: templates, onChange: onSettingsChanged)
        self.templateEditor = templateEditor
        let settingsView = SettingsView(
            settings: settings,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            hotKeyRegistrar: hotKeyRegistrar,
            captureController: captureController,
            templateEditor: templateEditor,
            permissionState: permissionState,
            storeHandle: storeHandle,
            onSelectTemplate: onSelectTemplate,
            onSettingsChanged: onSettingsChanged,
            onCheckForUpdates: onCheckForUpdates,
            onShowStack: onShowStack
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
        window.title = "Sendpoint"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "SettingsWindowToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        permissionState.stopWatchingVoiceModel()
        window = nil
        templateEditor?.teardown()
        templateEditor = nil
    }
}
