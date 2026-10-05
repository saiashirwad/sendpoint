import Foundation
import SendpointDomain

struct AppEnvironment {
    typealias StoreLoader = (@escaping @MainActor @Sendable () -> Void) async throws -> StackStore

    let loadStore: StoreLoader
    let appSettings: AppSettings
    let shortcutSettings: ShortcutSettings
    let templateSettings: TemplateSettings
    let voiceSettings: VoiceSettings
    let hotKeyCenter: HotKeyCenter
    let voiceService: VoiceNoteService
    let selectionMonitor: AutomaticSelectionMonitor
    let surfaces: SurfaceCoordinator
    let permissionState: PermissionController
    let hotKeyRegistrar: HotKeyRegistrar
    let exportController: ExportController
    let captureController: CaptureController
    let statusItemController: StatusItemController
    let updateController: UpdateController

    init(
        defaults: UserDefaults = .standard,
        hotKeyCenter: HotKeyCenter = .shared,
        exportServices: ExportServices? = nil,
        selectionCapture: SelectionCapture? = nil,
        captureSurfaces: ((CaptureController) -> CaptureSurfaces)? = nil,
        loadStore: @escaping StoreLoader = { onChange in
            try await StackStore(persistence: .live(diagnostics: Diag.record), onChange: onChange,
                                 diagnostics: Diag.record)
        }
    ) {
        let appSettings = AppSettings(defaults: defaults)
        let shortcutSettings = ShortcutSettings(defaults: defaults)
        let templateSettings = TemplateSettings(defaults: defaults)
        let voiceSettings = VoiceSettings(defaults: defaults)
        let transcriber = LocalStreamingTranscriber()
        let voiceService = VoiceNoteService(transcriber: transcriber)
        let selectionMonitor = AutomaticSelectionMonitor()
        let surfaces = SurfaceCoordinator()
        let permissionState = PermissionController(services: .live(transcriber: transcriber))
        let selection = selectionCapture ?? SelectionCapture.live(monitor: selectionMonitor)

        self.appSettings = appSettings
        self.loadStore = loadStore
        self.shortcutSettings = shortcutSettings
        self.templateSettings = templateSettings
        self.voiceSettings = voiceSettings
        self.hotKeyCenter = hotKeyCenter
        self.voiceService = voiceService
        self.selectionMonitor = selectionMonitor
        self.surfaces = surfaces
        self.permissionState = permissionState
        hotKeyRegistrar = HotKeyRegistrar(settings: shortcutSettings, center: hotKeyCenter)
        exportController = ExportController(services: exportServices ?? .live(selection: selection))
        captureController = CaptureController(
            settings: appSettings,
            voiceSettings: voiceSettings,
            permissionState: permissionState,
            selection: selection,
            recorder: .live(voiceService),
            surfaces: captureSurfaces ?? {
                .live(CaptureWindows(
                    model: $0,
                    surfaces: surfaces,
                    hotKeyCenter: hotKeyCenter
                ))
            }
        )
        statusItemController = StatusItemController()
        updateController = UpdateController()
    }
}
