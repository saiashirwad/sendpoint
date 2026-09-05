import AppKit
import SendpointDomain
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var setupWindowController: SetupWindowController?
    private var accessibilityHelperWindowController: AccessibilityHelperWindowController?
    private var profileEditor: ProfileEditorState?
    private var palette: StackPaletteWindowController?
    private enum StoreState {
        case loading
        case available(AnnotationStore)
        case unavailable(String)
    }

    private var storeState: StoreState = .loading
    private var bootstrapTask: Task<Void, Never>?
    private let exportController = ExportController()

    private var flashToken = 0
    private var flashing = false

    private let settings: AppSettings
    private let captureController: CaptureController
    private let permissionState: PermissionState
    private var voiceTrigger = VoiceTriggerMachine()

    override init() {
        let settings = AppSettings.shared
        let permissionState = PermissionState()
        self.settings = settings
        self.permissionState = permissionState
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
        setUpStatusItem()
        settings.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        settings.onProfilesChanged = { [weak self] in self?.refreshStatusItem() }
        settings.onInputDeviceChanged = { [settings] in
            VoiceAnnotationService.shared.preferredInputDeviceUID = settings.inputDeviceUID
        }
        VoiceAnnotationService.shared.preferredInputDeviceUID = settings.inputDeviceUID
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
        refreshStatusItem()
    }

    private var store: AnnotationStore? {
        guard case let .available(store) = storeState else { return nil }
        return store
    }

    private var unavailableMenuTitle: String {
        switch storeState {
        case .loading:
            return "Loading notes…"
        case .available:
            return "Nothing captured yet"
        case let .unavailable(message):
            return "Notes unavailable: \(message)"
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
        AutomaticSelectionMonitor.shared.teardown()
        store?.teardown()
        settings.onHotKeysChanged = nil
        settings.onProfilesChanged = nil
        settings.onInputDeviceChanged = nil
        for name in ShortcutSlot.allCases.map(\.rawValue) + ["voiceEscape"] {
            HotKeyCenter.shared.unregister(name: name)
        }
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

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Sendpoint")
        image?.isTemplate = true
        if let button = statusItem.button {
            button.image = image
            button.imagePosition = image == nil ? .noImage : .imageLeading
            if image == nil { button.title = "S" }
        }
        statusItem.isVisible = true
        rebuildMenu()
        Diag.log("statusItem button=\(statusItem.button != nil) image=\(image != nil) visible=\(statusItem.isVisible)")
    }

    private func refreshStatusItem() {
        if !flashing { applyCountTitle() }
        rebuildMenu()
    }

    private func applyCountTitle() {
        let count = store?.currentEntries.count ?? 0
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        let sessionName = store?.currentSession.name ?? "No stack"
        statusItem.button?.toolTip = "\(sessionName) · \(settings.activeProfile.name)"
    }

    private func flashStatus(_ text: String) {
        flashToken += 1
        let token = flashToken
        flashing = true
        statusItem.button?.title = " \(text)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.flashing = false
            self.applyCountTitle()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let ready = store != nil

        let voice = item("Voice Note (\(settings.voiceCaptureCombo.displayString))",
            action: ready ? #selector(captureVoiceSelection) : nil)
        voice.toolTip = settings.voiceCaptureCombo.displayString
        menu.addItem(voice)
        menu.addItem(item("Typed Note", action: ready ? #selector(captureSelection) : nil,
            combo: settings.captureCombo))
        menu.addItem(item("Show Stack…", action: ready ? #selector(showStack) : nil,
            combo: settings.stackCombo))

        let facts = store.map {
            SessionUIFacts(sessions: $0.sessions, currentSessionID: $0.currentSessionID, lastCleared: $0.lastCleared)
        }
        if let facts, facts.current != nil {
            menu.addItem(item(facts.currentTitle))
            let sessionMenu = NSMenu(title: "Stack")
            for session in facts.sessions {
                sessionMenu.addItem(item("\(session.name) — \(session.countLabel)",
                    action: #selector(switchToSession(_:)), represents: session.id, checked: session.isCurrent))
            }
            sessionMenu.addItem(.separator())
            sessionMenu.addItem(item("Switch Stack…", action: #selector(showQuickSwitcher),
                combo: settings.switchSessionCombo))
            let sessionRoot = item("Stack")
            sessionRoot.submenu = sessionMenu
            menu.addItem(sessionRoot)
        }

        let profileMenu = NSMenu(title: "Template")
        for profile in settings.profiles {
            profileMenu.addItem(item(profile.name, action: #selector(selectProfile(_:)),
                represents: profile.id, checked: profile.id == settings.activeProfileID))
        }
        let profileRoot = item("Template")
        profileRoot.submenu = profileMenu
        menu.addItem(profileRoot)
        menu.addItem(.separator())

        let count = facts?.current?.annotationCount ?? 0
        let verb = settings.pasteDirectly ? "Paste" : "Copy"
        menu.addItem(item(
            count > 0 ? "\(verb) \(count) Note\(count == 1 ? "" : "s") as Markdown" : unavailableMenuTitle,
            action: count > 0 ? #selector(copyMarkdown) : nil, combo: settings.copyCombo))
        menu.addItem(item(facts?.current.map { "Clear \($0.name)" } ?? "Clear Current Stack",
            action: count > 0 ? #selector(clearSession(_:)) : nil, represents: facts?.current?.id,
            combo: settings.clearCombo))
        if let undo = facts?.undo {
            let undoItem = item(undo.title, action: #selector(undoClear))
            undoItem.keyEquivalent = "z"
            menu.addItem(undoItem)
        }

        if let error = store?.error {
            menu.addItem(.separator())
            menu.addItem(item(annotationStoreErrorMessage(error)))
            if store?.hasPendingMutations == true {
                menu.addItem(item("Retry Pending Stack Changes", action: #selector(retryPendingMutations)))
            }
        }

        menu.addItem(.separator())
        let settingsItem = item("Settings…", action: #selector(showSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quit = item("Quit Sendpoint", action: #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// A menu item targeting this delegate. A valid global shortcut is shown
    /// beside it so it is discoverable; the Carbon hotkey swallows the event
    /// first, so it never double-fires.
    private func item(_ title: String, action: Selector? = nil, represents id: UUID? = nil,
                      checked: Bool = false, combo: KeyCombo? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.state = checked ? .on : .off
        if let combo, combo.isValid {
            if let equivalent = combo.menuKeyEquivalent {
                item.keyEquivalent = equivalent
                item.keyEquivalentModifierMask = combo.modifiers
            } else {
                item.toolTip = combo.displayString
            }
        }
        return item
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        handleVoiceTrigger(.configurationChanged(settings.voiceMode))
        let actions: [ShortcutSlot: () -> Void] = [
            .voiceCapture: { [weak self] in self?.handleVoiceTrigger(.pressed) },
            .capture: { [weak self] in self?.captureSelection() },
            .copy: { [weak self] in self?.copyMarkdown() },
            .stack: { [weak self] in self?.showStack() },
            .switchSession: { [weak self] in self?.showQuickSwitcher() },
            .clear: { [weak self] in self?.clearStack() },
        ]
        var issues: [ShortcutRegistrationIssue] = []
        for slot in ShortcutSlot.allCases {
            let combo = settings.combo(for: slot)
            // A rejected replacement must not leave the previous binding live.
            HotKeyCenter.shared.unregister(name: slot.rawValue)
            if let conflict = settings.shortcutConflict(for: combo, excluding: slot) {
                issues.append(.conflict(slot: slot, combo: combo, reason: conflict))
                continue
            }
            let released: (() -> Void)? = slot == .voiceCapture
                ? { [weak self] in self?.handleVoiceTrigger(.released) } : nil
            switch HotKeyCenter.shared.register(name: slot.rawValue, combo: combo, released: released,
                                                action: actions[slot]!) {
            case .registered: break
            case .invalid: issues.append(.invalid(slot: slot, combo: combo))
            case let .failed(status): issues.append(.unavailable(slot: slot, combo: combo, status: status))
            }
        }
        settings.updateShortcutRegistrationIssues(issues)
        rebuildMenu()
    }

    // MARK: - Actions

    @objc private func captureSelection() {
        Diag.log("captureSelection invoked")
        captureController.beginCapture()
    }

    @objc private func captureVoiceSelection() {
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

    @objc private func copyMarkdown() {
        guard let store else { NSSound.beep(); return }
        let target = settings.pasteDirectly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        exportController.copy(store: store, sessionID: store.currentSessionID,
            profile: settings.activeProfile, pasteTarget: target) { [weak self] message in
                self?.flashStatus(message)
            }
    }

    @objc private func clearStack() {
        guard let store else { NSSound.beep(); return }
        let sessionID = store.currentSessionID
        guard let session = store.sessions.first(where: { $0.id == sessionID }), !session.entries.isEmpty else {
            NSSound.beep()
            return
        }
        Diag.log("clearStack invoked, session=\(sessionID), count=\(session.entries.count)")
        enqueueMenuMutation(.clearSession(sessionID: sessionID))
    }

    @objc private func clearSession(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? UUID else { NSSound.beep(); return }
        enqueueMenuMutation(.clearSession(sessionID: sessionID))
    }

    @objc private func undoClear() {
        guard store != nil else { NSSound.beep(); return }
        enqueueMenuMutation(.undoClear)
    }

    @objc private func switchToSession(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? UUID else { NSSound.beep(); return }
        enqueueMenuMutation(.switchSession(sessionID: sessionID))
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? UUID else { NSSound.beep(); return }
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

    @objc private func retryPendingMutations() {
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
    @objc private func showStack() {
        guard let store else { NSSound.beep(); return }
        presentPalette(at: .notes(store.currentSessionID))
    }

    /// Opens the palette at the list of every stack.
    @objc private func showQuickSwitcher() {
        guard store != nil else { NSSound.beep(); return }
        presentPalette(at: .stacks)
    }

    private func presentPalette(at level: PaletteLevel) {
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
        palette?.show(at: level)
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
                    self.flashStatus("\(self.settings.voiceCaptureCombo.displayString): \(self.settings.voiceMode.detail) · Esc discards")
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

    @objc private func showSettings() {
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

    @objc private func quit() {
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
