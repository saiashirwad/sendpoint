import AppKit
import SendpointDomain

extension AppDelegate {
    func refreshStatusItem() {
        let count = store?.currentNotes.count ?? 0
        let stackName = store?.currentStack.name ?? "No stack"
        statusItemController.setBaseTitle(
            count > 0 ? " \(count)" : "",
            tooltip: "\(stackName) · \(templates.activeTemplate.name)"
        )
        statusItemController.rebuildMenu(
            facts: store.map {
                StackUIFacts(
                    stacks: $0.stacks,
                    currentStackID: $0.currentStackID,
                    lastCleared: $0.lastCleared
                )
            },
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
            copy: { [weak self] in self?.copyMarkdown() },
            showStack: { [weak self] in self?.showStack() },
            switchStack: { [weak self] reverse in self?.cycleStacks(reverse: reverse) },
            nextStack: { [weak self] in self?.nextStack() },
            previousStack: { [weak self] in self?.previousStack() },
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
        case .showStack: showStack()
        case let .switchToStack(stackID): switchToStack(stackID)
        case .quickSwitcher: showQuickSwitcher()
        case .nextStack: nextStack()
        case .previousStack: previousStack()
        case let .selectTemplate(templateID): requestTemplateSelection(templateID)
        case .copyMarkdown: copyMarkdown()
        case let .clearStack(stackID): clearStack(stackID)
        case .undoClear: undoClear()
        case .retryPendingMutations: retryPendingMutations()
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
        guard let store else { NSSound.beep(); return }
        let stackID = store.currentStackID
        guard let stack = store.stacks.first(where: { $0.id == stackID }), !stack.notes.isEmpty else {
            NSSound.beep()
            return
        }
        Diag.log("clearStack invoked, stack=\(stackID), count=\(stack.notes.count)")
        enqueueMenuMutation(.clearStack(stackID: stackID))
    }

    private func clearStack(_ stackID: UUID) {
        enqueueMenuMutation(.clearStack(stackID: stackID))
    }

    private func undoClear() {
        guard store != nil else { NSSound.beep(); return }
        enqueueMenuMutation(.undoClear)
    }

    private func switchToStack(_ stackID: UUID) {
        enqueueMenuMutation(.switchStack(stackID: stackID))
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

    private func showStack() {
        guard let store else { NSSound.beep(); return }
        presentPalette(at: .notes(store.currentStackID))
    }

    private func showQuickSwitcher() {
        guard store != nil else { NSSound.beep(); return }
        presentPalette(at: .stacks)
    }

    private func cycleStacks(reverse: Bool) {
        guard let switcher else { NSSound.beep(); return }
        switcher.press(reverse: reverse)
    }

    private func nextStack() {
        guard let switcher else { NSSound.beep(); return }
        switcher.step(1)
    }

    private func previousStack() {
        guard let switcher else { NSSound.beep(); return }
        switcher.step(-1)
    }

    func presentPalette(at level: PaletteLevel, highlighting stackID: UUID? = nil) {
        guard store != nil, let palette else { NSSound.beep(); return }
        palette.show(at: level, highlighting: stackID)
    }

    func buildPalette(store: StackStore) {
        palette = StackPaletteWindowController(
            store: store,
            settings: templates,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            export: exportController,
            surfaces: surfaces,
            onSelectTemplate: { [weak self] in self?.requestTemplateSelection($0) }
        )
    }

    func presentPermissionHelpForCapture() {
        permissionState.refresh()
        if settings.hasCompletedSetup {
            presentAccessibilityHelper()
        } else {
            presentSetup()
        }
    }

    func presentSetup() {
        permissionState.refresh()
        if setupWindowController == nil {
            setupWindowController = SetupWindowController(
                settings: settings,
                shortcuts: shortcuts,
                voiceSettings: voiceSettings,
                permissionState: permissionState,
                surfaces: surfaces,
                onShowAccessibilityHelper: { [weak self] in self?.presentAccessibilityHelper() },
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.surfaces.dismiss(.setup)
                    self.statusItemController.flash(
                        "\(self.shortcuts.voiceCaptureCombo.displayString): "
                            + "\(self.voiceSettings.voiceMode.detail) · Esc discards"
                    )
                }
            )
        }
        setupWindowController?.show()
    }

    func presentAccessibilityHelper() {
        if accessibilityHelperWindowController == nil {
            accessibilityHelperWindowController = AccessibilityHelperWindowController(
                permissionState: permissionState,
                surfaces: surfaces
            )
        }
        accessibilityHelperWindowController?.show()
    }

    private func showSettings() {
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
                onSelectTemplate: { [weak self] in self?.requestTemplateSelection($0) },
                onShowAccessibilityHelper: { [weak self] in self?.presentAccessibilityHelper() },
                onSettingsChanged: { [weak self] in self?.refreshStatusItem() }
            )
        }
        settingsWindowController?.show()
    }
}
