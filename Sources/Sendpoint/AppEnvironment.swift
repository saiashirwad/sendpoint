import Foundation

struct AppEnvironment {
    let appSettings: AppSettings
    let shortcutSettings: ShortcutSettings
    let templateSettings: TemplateSettings
    let voiceSettings: VoiceSettings
    let hotKeyCenter: HotKeyCenter
    let voiceService: VoiceNoteService
    let selectionMonitor: AutomaticSelectionMonitor
    let surfaces: SurfaceCoordinator
    let permissionState: PermissionState
    let hotKeyRegistrar: HotKeyRegistrar
    let exportController: ExportController
    let captureController: CaptureController
    let statusItemController: StatusItemController

    init(defaults: UserDefaults = .standard) {
        let appSettings = AppSettings(defaults: defaults)
        let shortcutSettings = ShortcutSettings(defaults: defaults)
        let templateSettings = TemplateSettings(defaults: defaults)
        let voiceSettings = VoiceSettings(defaults: defaults)
        let hotKeyCenter = HotKeyCenter.processCenter()
        let voiceService = VoiceNoteService()
        let selectionMonitor = AutomaticSelectionMonitor()
        let surfaces = SurfaceCoordinator()
        let permissionState = PermissionState(services: .live(voiceService: voiceService))
        let selection = SelectionCapture.live(monitor: selectionMonitor)

        self.appSettings = appSettings
        self.shortcutSettings = shortcutSettings
        self.templateSettings = templateSettings
        self.voiceSettings = voiceSettings
        self.hotKeyCenter = hotKeyCenter
        self.voiceService = voiceService
        self.selectionMonitor = selectionMonitor
        self.surfaces = surfaces
        self.permissionState = permissionState
        hotKeyRegistrar = HotKeyRegistrar(settings: shortcutSettings, center: hotKeyCenter)
        exportController = ExportController(services: .live(selection: selection))
        captureController = CaptureController(
            settings: appSettings,
            voiceSettings: voiceSettings,
            permissionState: permissionState,
            selection: selection,
            recorder: .live(voiceService),
            surfaces: {
                .live(CaptureWindows(
                    model: $0,
                    surfaces: surfaces,
                    hotKeyCenter: hotKeyCenter
                ))
            }
        )
        statusItemController = StatusItemController()
    }
}
