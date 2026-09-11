import AppKit
import SendpointDomain
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    let surfaces: SurfaceCoordinator
    var settingsWindowController: SettingsWindowController?
    var setupWindowController: SetupWindowController?
    var accessibilityHelperWindowController: AccessibilityHelperWindowController?
    var palette: StackPaletteWindowController?
    var switcher: StackSwitcherController?
    enum StoreState {
        case loading
        case available(StackStore)
        case unavailable(String)
    }

    var storeState: StoreState = .loading
    var bootstrapTask: Task<Void, Never>?
    var terminationTask: Task<Void, Never>?
    let exportController: ExportController

    let settings: AppSettings
    let captureController: CaptureController
    let permissionState: PermissionState
    let hotKeyRegistrar: HotKeyRegistrar

    override init() {
        let settings = AppSettings.shared
        let permissionState = PermissionState()
        let surfaces = SurfaceCoordinator()
        let selection = SelectionCapture.live(monitor: .shared)
        self.settings = settings
        self.permissionState = permissionState
        self.surfaces = surfaces
        self.hotKeyRegistrar = HotKeyRegistrar(settings: settings)
        self.exportController = ExportController(services: .live(selection: selection))
        self.captureController = CaptureController(
            settings: settings,
            permissionState: permissionState,
            selection: selection,
            recorder: .live(.shared),
            surfaces: { .live(CaptureWindows(model: $0, surfaces: surfaces)) }
        )
        super.init()
        captureController.onAccessibilityRequired = { [weak self] in
            self?.presentPermissionHelpForCapture()
        }
        captureController.onStatusChange = { [weak self] in
            self?.refreshStatusItem()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.log("=== launch pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        NSApp.mainMenu = MainMenu.build()
        statusItemController.onAction = { [weak self] action in self?.perform(action) }
        settings.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        settings.onTemplatesChanged = { [weak self] in self?.refreshStatusItem() }
        settings.onInputDeviceChanged = { [settings] in
            VoiceNoteService.shared.preferredInputDeviceUID = settings.inputDeviceUID
        }
        VoiceNoteService.shared.preferredInputDeviceUID = settings.inputDeviceUID
        VoiceNoteService.shared.warmUp()
        captureController.warmUp()
        registerHotKeys()
        permissionState.refresh()
        AutomaticSelectionMonitor.shared.start()

        bootstrapStore()
        if !settings.hasCompletedSetup {
            presentSetup()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissionState.refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if settingsWindowController?.canTerminate() == false { return .terminateCancel }
        guard let store, store.state == .processing else { return .terminateNow }
        // A save queued just before ⌘Q must reach disk before teardown cancels it.
        terminationTask = Task {
            await store.drain(timeout: .seconds(2))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminationTask?.cancel()
        terminationTask = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
        exportController.teardown()
        switcher?.teardown()
        switcher = nil
        palette?.teardown()
        palette = nil
        setupWindowController?.teardown()
        setupWindowController = nil
        accessibilityHelperWindowController?.teardown()
        accessibilityHelperWindowController = nil
        settingsWindowController?.teardown()
        settingsWindowController = nil
        captureController.teardown()
        permissionState.teardown()
        statusItemController.teardown()
        AutomaticSelectionMonitor.shared.teardown()
        store?.teardown()
        settings.onHotKeysChanged = nil
        settings.onTemplatesChanged = nil
        settings.onInputDeviceChanged = nil
        hotKeyRegistrar.unregisterAll()
        surfaces.teardown()
    }

}
