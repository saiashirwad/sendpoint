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
            voicePressed: { [weak self] in self?.sendCaptureEvent(.voicePressed) },
            voiceReleased: { [weak self] in self?.captureController.send(.voiceReleased) },
            typedNote: { [weak self] in self?.captureSelection() },
            dictatePressed: { [weak self] in self?.sendCaptureEvent(.dictatePressed) },
            dictateReleased: { [weak self] in self?.captureController.send(.dictateReleased) },
            copy: { [weak self] in self?.copyMarkdown() },
            showStack: { [weak self] in self?.showStack() },
            selectStack: { [weak self] number in self?.selectStack(number) },
            clear: { [weak self] in self?.clearStack() },
            editLatest: { [weak self] in self?.latestNoteEditor?.model.send(.open) }
        )
        let issues = hotKeyRegistrar.register(actions)
        shortcuts.updateShortcutRegistrationIssues(issues)
        refreshStatusItem()
    }

    func perform(_ action: StatusMenuAction) {
        switch action {
        case .voiceNote: sendCaptureEvent(.voiceToggled)
        case .typedNote: captureSelection()
        case .dictate: sendCaptureEvent(.dictateToggled)
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
        guard !focusOpenNoteEditor() else { return }
        Diag.log("captureSelection invoked")
        captureController.beginCapture()
    }

    private func sendCaptureEvent(_ event: CaptureEvent) {
        guard !focusOpenNoteEditor() else { return }
        captureController.send(event)
    }

    private func focusOpenNoteEditor() -> Bool {
        guard let editor = latestNoteEditor?.model, editor.isOpen else { return false }
        editor.send(.open)
        statusItemController.flash("Finish editing this note first.")
        return true
    }

    private func copyMarkdown() {
        guard !focusOpenNoteEditor() else { return }
        guard let store else { NSSound.beep(); return }
        let target = settings.pasteDirectly
            ? NSWorkspace.shared.frontmostApplication?.processIdentifier
            : nil
        exportController.copy(
            store: store,
            stackID: store.selectedStackID,
            template: templates.activeTemplate,
            pasteTarget: target
        ) { [weak self] message in
            self?.statusItemController.flash(message)
        }
    }

    private func clearStack() {
        guard let store, let stack = store.stack(id: store.selectedStackID), !stack.notes.isEmpty else {
            NSSound.beep()
            return
        }
        Diag.log("clearStack invoked, stack=\(stack.id), count=\(stack.notes.count)")
        clearStack(stack.id)
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
        guard !focusOpenNoteEditor() else { return }
        guard store != nil, let palette else { NSSound.beep(); return }
        palette.show()
    }

    private func selectStack(_ number: Int) {
        guard let stackSelector else { NSSound.beep(); return }
        stackSelector.select(number)
    }
}
