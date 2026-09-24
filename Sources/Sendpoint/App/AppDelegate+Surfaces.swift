import AppKit
import SendpointDomain

extension AppDelegate {
    func buildPalette(store: StackStore) {
        palette = StackPaletteWindowController(
            store: store,
            settings: templates,
            shortcuts: shortcuts,
            export: exportController,
            surfaces: surfaces,
            onSelectTemplate: { [weak self] in self?.requestTemplateSelection($0) }
        )
    }

    func presentPermissionHelpForCapture() {
        permissionState.refresh()
        if settings.hasCompletedSetup {
            permissionState.requestAccessibility()
        } else {
            presentSetup()
        }
    }

    func presentSetup() {
        permissionState.refresh()
        if setupWindowController == nil {
            setupWindowController = SetupWindowController(
                settings: settings,
                permissionState: permissionState,
                shortcuts: shortcuts,
                voiceSettings: voiceSettings,
                surfaces: surfaces,
                noteCount: { [weak self] in self?.store.map(SetupTour.noteCount(in:)) },
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.surfaces.dismiss(.setup)
                    self.refreshStatusItem()
                }
            )
        }
        setupWindowController?.show()
    }

    func presentLaunchSurface(kind: LaunchPresentation.Kind) {
        switch LaunchPresentation.decide(hasCompletedSetup: settings.hasCompletedSetup, kind: kind) {
        case .setup: presentSetup()
        case .settings: showSettings()
        case .none: break
        }
    }

    func observeUserOpened() {
        guard userOpenedObserver == nil else { return }
        userOpenedObserver = DistributedNotificationCenter.default().addObserver(
            forName: LaunchPresentation.userOpenedNotification,
            object: Bundle.main.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.presentLaunchSurface(kind: .userOpen)
            }
        }
    }

    func showSettings() {
        guard settings.hasCompletedSetup else {
            presentSetup()
            return
        }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                shortcuts: shortcuts,
                templates: templates,
                voiceSettings: voiceSettings,
                hotKeyRegistrar: hotKeyRegistrar,
                captureController: captureController,
                permissionState: permissionState,
                surfaces: surfaces,
                stackStore: store,
                onSelectTemplate: { [weak self] in self?.requestTemplateSelection($0) },
                onSettingsChanged: { [weak self] in self?.refreshStatusItem() },
                onCheckForUpdates: { [weak self] in self?.updateController.checkForUpdates() },
                onShowStack: { [weak self] in self?.showStack() }
            )
        }
        settingsWindowController?.show()
    }
}
