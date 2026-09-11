import AppKit
import SendpointDomain
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private var settingsWindow: NSWindow?
    private var setupWindowController: SetupWindowController?
    private var accessibilityHelperWindowController: AccessibilityHelperWindowController?
    private var profileEditor: ProfileEditorState?
    private var palette: StackPaletteWindowController?
    private var switcher: StackSwitcherController?
    private enum StoreState {
        case loading
        case available(AnnotationStore)
        case unavailable(String)
    }

    private var storeState: StoreState = .loading
    private var bootstrapTask: Task<Void, Never>?
    private let exportController = ExportController()

    private let settings: AppSettings
    private let captureController: CaptureController
    private let permissionState: PermissionState
    private let hotKeyRegistrar: HotKeyRegistrar
    private var voiceTrigger = VoiceTriggerMachine()

    override init() {
        let settings = AppSettings.shared
        let permissionState = PermissionState()
        self.settings = settings
        self.permissionState = permissionState
        self.hotKeyRegistrar = HotKeyRegistrar(settings: settings)
        self.captureController = CaptureController(
            settings: settings,
            permissionState: permissionState
        )
        super.init()
        captureController.onAccessibilityRequired = { [weak self] in
            self?.presentPermissionHelpForCapture()
        }
        captureController.onStatusChange = { [weak self] in
            self?.refreshStatusItem()
        }
        captureController.onVoiceCaptureEnded = { [weak self] in
            self?.handleVoiceTrigger(.captureEnded)
        }
        captureController.onVoiceEscape = { [weak self] in
            self?.handleVoiceTrigger(.escape)
        }
        captureController.onWillPresentEditor = { [weak self] in
            self?.hideAuxiliaryWindows()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diag.log("=== launch pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        installMainMenu()
        statusItemController.onAction = { [weak self] action in self?.perform(action) }
        settings.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        settings.onProfilesChanged = { [weak self] in self?.refreshStatusItem() }
        settings.onInputDeviceChanged = { [settings] in
            VoiceAnnotationService.shared.preferredInputDeviceUID = settings.inputDeviceUID
        }
        VoiceAnnotationService.shared.preferredInputDeviceUID = settings.inputDeviceUID
        VoiceAnnotationService.shared.warmUp()
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
                let store = try await AnnotationStore(
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
                switcher = StackSwitcherController(
                    store: store, settings: settings,
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

    private var store: AnnotationStore? {
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
        guard let profileEditor else { return .terminateNow }
        return ProfileDialogs.shouldClose(profileEditor) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        exportController.teardown()
        switcher?.teardown()
        switcher = nil
        palette?.teardown()
        setupWindowController?.teardown()
        setupWindowController = nil
        accessibilityHelperWindowController?.teardown()
        accessibilityHelperWindowController = nil
        settingsWindow?.delegate = nil
        settingsWindow?.close()
        settingsWindow = nil
        captureController.teardown()
        permissionState.teardown()
        statusItemController.teardown()
        AutomaticSelectionMonitor.shared.teardown()
        store?.teardown()
        settings.onHotKeysChanged = nil
        settings.onProfilesChanged = nil
        settings.onInputDeviceChanged = nil
        hotKeyRegistrar.unregisterAll()
    }

    // MARK: - Main menu

    /// A menu-bar app has no visible main menu, but AppKit still routes ⌘V,
    /// ⌘C, ⌘A and ⌘Z through one. Without it, a dictation tool that types by
    /// sending ⌘V to the note box gets nothing — the text stays stuck on the
    /// clipboard and turns up later, on top of the Markdown.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Sendpoint")
        main.addItem(appItem)

        let file = NSMenu(title: "File")
        file.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: - Status item

    private func refreshStatusItem() {
        let count = store?.currentEntries.count ?? 0
        let sessionName = store?.currentSession.name ?? "No stack"
        statusItemController.setBaseTitle(
            count > 0 ? " \(count)" : "",
            tooltip: "\(sessionName) · \(settings.activeProfile.name)"
        )
        statusItemController.rebuildMenu(
            facts: store.map {
                SessionUIFacts(
                    sessions: $0.sessions,
                    currentSessionID: $0.currentSessionID,
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
        handleVoiceTrigger(.configurationChanged(settings.voiceMode))
        let actions = HotKeyRegistrar.Actions(
            voicePressed: { [weak self] in self?.handleVoiceTrigger(.pressed) },
            voiceReleased: { [weak self] in self?.handleVoiceTrigger(.released) },
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
        case let .switchToStack(sessionID):
            switchToSession(sessionID)
        case .quickSwitcher:
            showQuickSwitcher()
        case .nextStack:
            nextStack()
        case .previousStack:
            previousStack()
        case let .selectProfile(profileID):
            selectProfile(profileID)
        case .copyMarkdown:
            copyMarkdown()
        case let .clearSession(sessionID):
            clearSession(sessionID)
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
        handleVoiceTrigger(.menuToggle)
    }

    private func handleVoiceTrigger(_ event: VoiceTriggerEvent) {
        runVoiceCommands(voiceTrigger.handle(event))
    }

    private func runVoiceCommands(_ commands: [VoiceTriggerCommand]) {
        for command in commands {
            switch command {
            case .beginCapture:
                captureController.beginVoiceCapture()
            case .finishCapture:
                captureController.endVoiceCapture()
            case .cancelCapture:
                captureController.cancelVoiceCapture()
            }
        }
    }

    private func copyMarkdown() {
        guard let store else { NSSound.beep(); return }
        let target = settings.pasteDirectly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        exportController.copy(store: store, sessionID: store.currentSessionID,
            profile: settings.activeProfile, pasteTarget: target) { [weak self] message in
                self?.statusItemController.flash(message)
            }
    }

    private func clearStack() {
        guard let store else { NSSound.beep(); return }
        let sessionID = store.currentSessionID
        guard let session = store.sessions.first(where: { $0.id == sessionID }), !session.entries.isEmpty else {
            NSSound.beep()
            return
        }
        Diag.log("clearStack invoked, session=\(sessionID), count=\(session.entries.count)")
        enqueueMenuMutation(.clearSession(sessionID: sessionID))
    }

    private func clearSession(_ sessionID: UUID) {
        enqueueMenuMutation(.clearSession(sessionID: sessionID))
    }

    private func undoClear() {
        guard store != nil else { NSSound.beep(); return }
        enqueueMenuMutation(.undoClear)
    }

    private func switchToSession(_ sessionID: UUID) {
        enqueueMenuMutation(.switchSession(sessionID: sessionID))
    }

    private func selectProfile(_ profileID: UUID) {
        requestProfileSelection(profileID)
    }

    private func requestProfileSelection(_ profileID: UUID) {
        if let profileEditor {
            switch profileEditor.requestSelection(profileID) {
            case .needsDecision:
                _ = ProfileDialogs.resolvePendingSelection(profileEditor)
            case .selected, .unchanged:
                break
            case .rejected:
                NSSound.beep()
            }
            return
        }
        do {
            try settings.selectProfile(id: profileID)
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

    private func enqueueMenuMutation(_ mutation: SessionDocumentMutation) {
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
        presentPalette(at: .notes(store.currentSessionID))
    }

    /// Opens the palette at the list of every stack.
    private func showQuickSwitcher() {
        guard store != nil else { NSSound.beep(); return }
        presentPalette(at: .stacks)
    }

    /// The switch shortcut: ⌘⇥ for stacks. A pinned palette gives way to it.
    private func cycleStacks(reverse: Bool) {
        guard let switcher else { NSSound.beep(); return }
        palette?.close()
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

    private func presentPalette(at level: PaletteLevel, highlighting sessionID: UUID? = nil) {
        guard let store else { NSSound.beep(); return }
        if palette == nil {
            palette = StackPaletteWindowController(
                store: store,
                settings: settings,
                export: exportController,
                onSelectProfile: { [weak self] profileID in
                    self?.requestProfileSelection(profileID)
                },
                onDismiss: { [weak self] in self?.palette = nil }
            )
        }
        palette?.show(at: level, highlighting: sessionID)
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
                onShowAccessibilityHelper: { [weak self] in
                    self?.presentAccessibilityHelper()
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    self.setupWindowController?.close()
                    self.statusItemController.flash("\(self.settings.voiceCaptureCombo.displayString): \(self.settings.voiceMode.detail) · Esc discards")
                }
            )
        }
        setupWindowController?.show()
    }

    private func presentAccessibilityHelper() {
        if accessibilityHelperWindowController == nil {
            accessibilityHelperWindowController = AccessibilityHelperWindowController(
                permissionState: permissionState
            )
        }
        accessibilityHelperWindowController?.show()
    }

    private func showSettings() {
        permissionState.refresh()
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "SettingsWindowToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let profileEditor = ProfileEditorState(settings: settings)
        self.profileEditor = profileEditor
        let settingsView = SettingsView(
            settings: settings,
            profileEditor: profileEditor,
            permissionState: permissionState,
            onSelectProfile: { [weak self] profileID in
                self?.requestProfileSelection(profileID)
            },
            onShowAccessibilityHelper: { [weak self] in
                self?.presentAccessibilityHelper()
            }
        )
        let hosting = NSHostingView(rootView: settingsView)
        // The sidebar owns the title-bar band; no inset for the toolbar.
        hosting.safeAreaRegions = []
        // SwiftUI publishes only its minimum, so the window never shrinks
        // below it and never resizes itself when a tab changes.
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.contentMinSize = SettingsView.size
        window.setContentSize(SettingsView.size)
        window.center()
        // Remembers a larger size between openings, if the user made one.
        window.setFrameAutosaveName("SettingsWindow")
        window.delegate = self
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Open calmly, without the first text field selected.
        window.makeFirstResponder(nil)
    }

    /// Tuck away auxiliary windows so a capture shows the note box alone.
    private func hideAuxiliaryWindows() {
        Diag.log("hideAuxiliaryWindows palette=\(palette != nil) settings=\(settingsWindow?.isVisible ?? false)")
        settingsWindow?.orderOut(nil)
        setupWindowController?.close()
        accessibilityHelperWindowController?.close()
        palette?.close()
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === settingsWindow else { return frameSize }
        let minimum = sender.frameRect(forContentRect: NSRect(origin: .zero, size: SettingsView.size)).size
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === settingsWindow, let profileEditor else { return true }
        return ProfileDialogs.shouldClose(profileEditor)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
            profileEditor = nil
        }
    }
}
