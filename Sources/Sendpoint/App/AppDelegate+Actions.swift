import AppKit
import SendpointDomain

extension AppDelegate {
    func refreshStatusItem() {
        let facts = store.map(StackUIFacts.init(store:))
        let current = facts?.current
        statusItemController.setBaseTitle(
            StatusMenuModel.title(for: current),
            tooltip: "\(current?.name ?? "No stack") · \(templates.activeTemplate.name)"
        )
        statusItemController.rebuildMenu(
            facts: facts,
            storeStatus: statusMenuStoreStatus,
            error: store?.error,
            hasPendingMutations: store?.hasPendingMutations == true,
            settings: settings,
            shortcuts: shortcuts,
            templates: templates
        )
    }

    func registerHotKeys() {
        captureController.send(.voiceModeChanged(voiceSettings.voiceMode))
        let actions = HotKeyRegistrar.Actions(
            voicePressed: { [weak self] in self?.captureController.send(.voicePressed) },
            voiceReleased: { [weak self] in self?.captureController.send(.voiceReleased) },
            typedNote: { [weak self] in self?.captureSelection() },
            dictatePressed: { [weak self] in self?.captureController.send(.dictatePressed) },
            dictateReleased: { [weak self] in self?.captureController.send(.dictateReleased) },
            copy: { [weak self] in self?.copyMarkdown() },
            showStack: { [weak self] in self?.showStack() },
            selectStack: { [weak self] number in self?.selectStack(number) },
            clear: { [weak self] in self?.clearStack() }
        )
        let issues = hotKeyRegistrar.register(actions)
        shortcuts.updateShortcutRegistrationIssues(issues)
        refreshStatusItem()
    }

    func perform(_ action: StatusMenuAction) {
        switch action {
        case .voiceNote: captureController.send(.voiceToggled)
        case .typedNote: captureSelection()
        case .dictate: captureController.send(.dictateToggled)
        case .showStack: showStack()
        case let .selectStack(number): selectStack(number)
        case let .selectTemplate(templateID): requestTemplateSelection(templateID)
        case .copyMarkdown: copyMarkdown()
        case let .clearStack(stackID): clearStack(stackID)
        case .undoClear: undoClear()
        case .retryPendingMutations: retryPendingMutations()
        case .checkForUpdates: updateController.checkForUpdates()
        case .settings: showSettings()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func captureSelection() {
        Diag.log("captureSelection invoked")
        captureController.beginCapture()
    }

    private func copyMarkdown() {
        guard let store else { NSSound.beep(); return }
        let target = settings.pasteDirectly
            ? NSWorkspace.shared.frontmostApplication?.processIdentifier
            : nil
        exportController.copy(
            store: store,
            stackID: store.currentStackID,
            template: templates.activeTemplate,
            pasteTarget: target
        ) { [weak self] message in
            self?.statusItemController.flash(message)
        }
    }

    private func clearStack() {
        guard let store, !store.currentNotes.isEmpty else { NSSound.beep(); return }
        Diag.log("clearStack invoked, stack=\(store.currentStackID), count=\(store.currentNotes.count)")
        clearStack(store.currentStackID)
    }

    private func clearStack(_ stackID: UUID) {
        enqueueMenuMutation(.clearStack(stackID: stackID))
    }

    private func undoClear() {
        enqueueMenuMutation(.undoClear)
    }

    func requestTemplateSelection(_ templateID: UUID) {
        if settingsWindowController?.requestTemplateSelection(templateID) == true { return }
        do {
            try templates.selectTemplate(id: templateID)
            refreshStatusItem()
        } catch {
            NSSound.beep()
        }
    }

    private func retryPendingMutations() {
        guard let store else { NSSound.beep(); return }
        store.retryPendingMutations()
        exportController.send(.retry)
        refreshStatusItem()
    }

    private func enqueueMenuMutation(_ mutation: StackDocumentMutation) {
        guard let store else { NSSound.beep(); return }
        store.mutate(mutation) { [weak self] outcome in
            self?.refreshStatusItem()
            if case .rejected = outcome { NSSound.beep() }
            if case .commitFailed = outcome { NSSound.beep() }
        }
    }

    func showStack() {
        guard store != nil, let palette else { NSSound.beep(); return }
        palette.show()
    }

    private func selectStack(_ number: Int) {
        guard let stackSelector else { NSSound.beep(); return }
        stackSelector.select(number)
    }

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

    private func showSettings() {
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
