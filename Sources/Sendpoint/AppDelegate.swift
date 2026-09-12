import AppKit
import SendpointDomain
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    var statusItemController: StatusItemController { environment.statusItemController }
    var surfaces: SurfaceCoordinator { environment.surfaces }
    var settings: AppSettings { environment.appSettings }
    var shortcuts: ShortcutSettings { environment.shortcutSettings }
    var templates: TemplateSettings { environment.templateSettings }
    var voiceSettings: VoiceSettings { environment.voiceSettings }
    var captureController: CaptureController { environment.captureController }
    var permissionState: PermissionState { environment.permissionState }
    var hotKeyRegistrar: HotKeyRegistrar { environment.hotKeyRegistrar }
    var exportController: ExportController { environment.exportController }
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
    var userOpenedObserver: (any NSObjectProtocol)?
    override init() {
        environment = AppEnvironment()
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
        observeUserOpened()
        NSApp.mainMenu = MainMenu.build()
        statusItemController.onAction = { [weak self] action in self?.perform(action) }
        captureController.warmUp()
        registerHotKeys()
        permissionState.refresh()
        environment.selectionMonitor.start()

        bootstrapStore()
        presentLaunchSurface(kind: .fromCurrentAppleEvent())
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentLaunchSurface(kind: .userOpen)
        return false
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
        if let userOpenedObserver {
            DistributedNotificationCenter.default().removeObserver(userOpenedObserver)
            self.userOpenedObserver = nil
        }
        captureController.teardown()
        permissionState.teardown()
        statusItemController.teardown()
        environment.selectionMonitor.teardown()
        store?.teardown()
        hotKeyRegistrar.unregisterAll()
        surfaces.teardown()
    }

}
