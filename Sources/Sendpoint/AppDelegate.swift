import AppKit
import SendpointDomain
import SwiftUI
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private let surfaces: SurfaceCoordinator
    private var settingsWindowController: SettingsWindowController?
    private var setupWindowController: SetupWindowController?
    private var accessibilityHelperWindowController: AccessibilityHelperWindowController?
    private var palette: StackPaletteWindowController?
    private var switcher: StackSwitcherController?
    private enum StoreState {
        case loading
        case available(StackStore)
        case unavailable(String)
    }

    private var storeState: StoreState = .loading
    private var bootstrapTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private let exportController: ExportController

    private let settings: AppSettings
    private let captureController: CaptureController
    private let permissionState: PermissionState
    private let hotKeyRegistrar: HotKeyRegistrar

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

    private func bootstrapStore() {
        bootstrapTask?.cancel()
        storeState = .loading
        refreshStatusItem()

        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            do {
                let store = try await StackStore(
                    persistence: .live(),
                    onChange: { [weak self] in self?.storeDidChange() }
                )
                guard !Task.isCancelled else {
                    store.teardown()
                    return
                }
                bootstrapTask = nil
                storeState = .available(store)
                captureController.configure(store: store)
                buildPalette(store: store)
                switcher = StackSwitcherController(
                    store: store, settings: settings,
                    surfaces: surfaces,
                    onOpenPalette: { [weak self] id in self?.presentPalette(at: .stacks, highlighting: id) },
                    onSwitched: { [weak self] stack in self?.statusItemController.flash(stack.name) }
                )
                refreshStatusItem()
            } catch is CancellationError {
                // App termination owns cancellation and teardown.
            } catch {
                guard !Task.isCancelled else { return }
                bootstrapTask = nil
                storeState = .unavailable(error.localizedDescription)
                Diag.log("store bootstrap failed: \(error)")
                refreshStatusItem()
            }
        }
    }

    private func storeDidChange() {
        palette?.documentChanged()
        switcher?.documentChanged()
        refreshStatusItem()
    }

    private var store: StackStore? {
        guard case let .available(store) = storeState else { return nil }
        return store
    }

    private var statusMenuStoreStatus: StatusMenuStoreStatus {
        switch storeState {
        case .loading:
            .loading
        case .available:
            .available
        case let .unavailable(message):
            .unavailable(message)
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

    // MARK: - Status item

    private func refreshStatusItem() {
        let count = store?.currentNotes.count ?? 0
        let stackName = store?.currentStack.name ?? "No stack"
        statusItemController.setBaseTitle(
            count > 0 ? " \(count)" : "",
            tooltip: "\(stackName) · \(settings.activeTemplate.name)"
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
            settings: settings
        )
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        captureController.send(.voiceModeChanged(settings.voiceMode))
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
        settings.updateShortcutRegistrationIssues(issues)
        refreshStatusItem()
    }

    // MARK: - Actions

    private func perform(_ action: StatusMenuAction) {
        switch action {
        case .voiceNote:
            captureVoiceSelection()
        case .typedNote:
            captureSelection()
        case .showStack:
            showStack()
        case let .switchToStack(stackID):
            switchToStack(stackID)
        case .quickSwitcher:
            showQuickSwitcher()
        case .nextStack:
            nextStack()
        case .previousStack:
            previousStack()
        case let .selectTemplate(templateID):
            selectTemplate(templateID)
        case .copyMarkdown:
            copyMarkdown()
        case let .clearStack(stackID):
            clearStack(stackID)
        case .undoClear:
            undoClear()
        case .retryPendingMutations:
            retryPendingMutations()
        case .settings:
            showSettings()
        case .quit:
            quit()
        }
    }

    private func captureSelection() {
        Diag.log("captureSelection invoked")
        captureController.beginCapture()
    }

    private func captureVoiceSelection() {
        Diag.log("voice capture invoked")
        captureController.send(.voiceToggled)
    }

    private func copyMarkdown() {
        guard let store else { NSSound.beep(); return }
        let target = settings.pasteDirectly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        exportController.copy(store: store, stackID: store.currentStackID,
            template: settings.activeTemplate, pasteTarget: target) { [weak self] message in
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

    private func selectTemplate(_ templateID: UUID) {
        requestTemplateSelection(templateID)
    }

    private func requestTemplateSelection(_ templateID: UUID) {
        if settingsWindowController?.requestTemplateSelection(templateID) == true { return }
        do {
            try settings.selectTemplate(id: templateID)
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

    /// Opens the palette inside the current stack: its notes, full width.
    private func showStack() {
        guard let store else { NSSound.beep(); return }
        presentPalette(at: .notes(store.currentStackID))
    }

    /// Opens the palette at the list of every stack.
    private func showQuickSwitcher() {
        guard store != nil else { NSSound.beep(); return }
        presentPalette(at: .stacks)
    }

    /// The switch shortcut: ⌘⇥ for stacks. A pinned palette gives way to it.
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

    private func presentPalette(at level: PaletteLevel, highlighting stackID: UUID? = nil) {
        guard store != nil else { NSSound.beep(); return }
        guard let palette else { NSSound.beep(); return }
        palette.show(at: level, highlighting: stackID)
    }

    private func buildPalette(store: StackStore) {
        palette = StackPaletteWindowController(
                store: store,
                settings: settings,
                export: exportController,
                surfaces: surfaces,
                onSelectTemplate: { [weak self] templateID in
                    self?.requestTemplateSelection(templateID)
                }
            )
    }

    private func presentPermissionHelpForCapture() {
        permissionState.refresh()
        if settings.hasCompletedSetup {
            presentAccessibilityHelper()
        } else {
            presentSetup()
        }
    }

    private func presentSetup() {
        permissionState.refresh()
        if setupWindowController == nil {
            setupWindowController = SetupWindowController(
                settings: settings,
                permissionState: permissionState,
                surfaces: surfaces,
                onShowAccessibilityHelper: { [weak self] in
                    self?.presentAccessibilityHelper()
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.surfaces.dismiss(.setup)
                    self.statusItemController.flash("\(self.settings.voiceCaptureCombo.displayString): \(self.settings.voiceMode.detail) · Esc discards")
                }
            )
        }
        setupWindowController?.show()
    }

    private func presentAccessibilityHelper() {
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
                permissionState: permissionState,
                surfaces: surfaces,
                onSelectTemplate: { [weak self] in self?.requestTemplateSelection($0) },
                onShowAccessibilityHelper: { [weak self] in self?.presentAccessibilityHelper() }
            )
        }
        settingsWindowController?.show()
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
