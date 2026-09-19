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
    var updateController: UpdateController { environment.updateController }
    var settingsWindowController: SettingsWindowController?
    var setupWindowController: SetupWindowController?
    var palette: StackPaletteWindowController?
    var stackSelector: StackSelector?
    var stackReadout: StackReadoutController?
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
        environment.voiceService.teardown()
        guard let store, store.state == .processing else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task {
            await store.drain(timeout: .seconds(2))
            guard !Task.isCancelled else { return }
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
        stackSelector?.teardown()
        stackSelector = nil
        stackReadout?.teardown()
        stackReadout = nil
        palette?.teardown()
        palette = nil
        setupWindowController?.teardown()
        setupWindowController = nil
        settingsWindowController?.teardown()
        settingsWindowController = nil
        if let userOpenedObserver {
            DistributedNotificationCenter.default().removeObserver(userOpenedObserver)
            self.userOpenedObserver = nil
        }
        environment.voiceService.teardown()
        captureController.teardown()
        permissionState.teardown()
        statusItemController.teardown()
        environment.selectionMonitor.teardown()
        store?.teardown()
        hotKeyRegistrar.unregisterAll()
        surfaces.teardown()
    }

}
