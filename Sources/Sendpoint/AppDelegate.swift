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
    private var captureObserver: NSObjectProtocol?

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

        // The capture panel needs the app frontmost to take keystrokes, and
        // activating brings every window forward. Get the others out of the way.
        captureObserver = NotificationCenter.default.addObserver(
            forName: .captureWillPresent, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideAuxiliaryWindows() }
        }

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

    private var isStoreAvailable: Bool { store != nil }

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
        if let captureObserver {
            NotificationCenter.default.removeObserver(captureObserver)
            self.captureObserver = nil
        }
        settings.onHotKeysChanged = nil
        settings.onProfilesChanged = nil
        settings.onInputDeviceChanged = nil
        for name in ["voiceCapture", "capture", "voiceEscape", "copy", "stack", "switchSession", "clear"] {
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

        let voice = NSMenuItem(
            title: "Voice Note (\(settings.voiceCaptureCombo.displayString))",
            action: isStoreAvailable ? #selector(captureVoiceSelection) : nil,
            keyEquivalent: ""
        )
        voice.target = self
        voice.toolTip = settings.voiceCaptureCombo.displayString
        menu.addItem(voice)

        let capture = NSMenuItem(
            title: "Typed Note",
            action: isStoreAvailable ? #selector(captureSelection) : nil,
            keyEquivalent: ""
        )
        capture.target = self
        apply(settings.captureCombo, to: capture)
        menu.addItem(capture)

        let show = NSMenuItem(
            title: "Show Stack…",
            action: isStoreAvailable ? #selector(showStack) : nil,
            keyEquivalent: ""
        )
        show.target = self
        apply(settings.stackCombo, to: show)
        menu.addItem(show)

        let facts = store.map {
            SessionUIFacts(
                sessions: $0.sessions,
                currentSessionID: $0.currentSessionID,
                lastCleared: $0.lastCleared
            )
        }
        if let facts, let current = facts.current {
            let summary = NSMenuItem(title: facts.currentTitle, action: nil, keyEquivalent: "")
            menu.addItem(summary)

            let sessionMenu = NSMenu(title: "Stack")
            for session in facts.sessions {
                let item = NSMenuItem(
                    title: "\(session.name) — \(session.annotationCount) note\(session.annotationCount == 1 ? "" : "s")",
                    action: #selector(switchToSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.id as NSUUID
                item.state = session.isCurrent ? .on : .off
                sessionMenu.addItem(item)
            }
            sessionMenu.addItem(.separator())

            let quickSwitch = NSMenuItem(
                title: "Switch Stack…",
                action: #selector(showQuickSwitcher),
                keyEquivalent: ""
            )
            quickSwitch.target = self
            apply(settings.switchSessionCombo, to: quickSwitch)
            sessionMenu.addItem(quickSwitch)
            sessionMenu.addItem(.separator())

            let newSession = NSMenuItem(
                title: "New Stack…",
                action: #selector(newSession(_:)),
                keyEquivalent: ""
            )
            newSession.target = self
            sessionMenu.addItem(newSession)

            let rename = NSMenuItem(
                title: "Rename Current Stack…",
                action: #selector(renameSession(_:)),
                keyEquivalent: ""
            )
            rename.target = self
            rename.representedObject = current.id as NSUUID
            sessionMenu.addItem(rename)

            let delete = NSMenuItem(
                title: "Delete Current Stack…",
                action: facts.canDelete ? #selector(deleteSession(_:)) : nil,
                keyEquivalent: ""
            )
            delete.target = self
            delete.representedObject = current.id as NSUUID
            sessionMenu.addItem(delete)

            let sessionRoot = NSMenuItem(title: "Stack", action: nil, keyEquivalent: "")
            sessionRoot.submenu = sessionMenu
            menu.addItem(sessionRoot)
        }

        let profileMenu = NSMenu(title: "Template")
        for profile in settings.profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.id as NSUUID
            item.state = profile.id == settings.activeProfileID ? .on : .off
            profileMenu.addItem(item)
        }
        let profileRoot = NSMenuItem(title: "Template", action: nil, keyEquivalent: "")
        profileRoot.submenu = profileMenu
        menu.addItem(profileRoot)

        menu.addItem(.separator())

        let count = facts?.current?.annotationCount ?? 0
        let verb = settings.pasteDirectly ? "Paste" : "Copy"
        let copy = NSMenuItem(
            title: count > 0
                ? "\(verb) \(count) Note\(count == 1 ? "" : "s") as Markdown"
                : unavailableMenuTitle,
            action: count > 0 ? #selector(copyMarkdown) : nil,
            keyEquivalent: ""
        )
        copy.target = self
        apply(settings.copyCombo, to: copy)
        menu.addItem(copy)

        let clear = NSMenuItem(
            title: facts?.current.map { "Clear \($0.name)" } ?? "Clear Current Stack",
            action: count > 0 ? #selector(clearSession(_:)) : nil,
            keyEquivalent: ""
        )
        clear.target = self
        clear.representedObject = facts?.current?.id as NSUUID?
        apply(settings.clearCombo, to: clear)
        menu.addItem(clear)

        if let undo = facts?.undo {
            let item = NSMenuItem(
                title: undo.title,
                action: #selector(undoClear),
                keyEquivalent: "z"
            )
            item.keyEquivalentModifierMask = [.command]
            item.target = self
            menu.addItem(item)
        }

        if let error = store?.error {
            menu.addItem(.separator())
            let errorItem = NSMenuItem(
                title: annotationStoreErrorMessage(error),
                action: nil,
                keyEquivalent: ""
            )
            menu.addItem(errorItem)
            if store?.hasPendingMutations == true {
                let retry = NSMenuItem(
                    title: "Retry Pending Stack Changes",
                    action: #selector(retryPendingMutations),
                    keyEquivalent: ""
                )
                retry.target = self
                menu.addItem(retry)
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit Sendpoint", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Show the global shortcut beside the menu item so it is discoverable.
    /// The Carbon hotkey swallows the event first, so this never double-fires.
    private func apply(_ combo: KeyCombo, to item: NSMenuItem) {
        guard combo.isValid else { return }
        if let equivalent = combo.menuKeyEquivalent {
            item.keyEquivalent = equivalent
            item.keyEquivalentModifierMask = combo.modifiers
        } else {
            item.toolTip = combo.displayString
        }
    }

    // MARK: - Hot keys

    private func registerHotKeys() {
        handleVoiceTrigger(.configurationChanged(settings.voiceMode))
        var issues: [ShortcutRegistrationIssue] = []

        func register(
            _ slot: ShortcutSlot,
            combo: KeyCombo,
            operation: () -> HotKeyRegistrationResult
        ) {
            // A rejected replacement must not leave the previous binding live.
            HotKeyCenter.shared.unregister(name: slot.rawValue)
            if let conflict = settings.shortcutConflict(for: combo, excluding: slot) {
                issues.append(.conflict(slot: slot, combo: combo, reason: conflict))
                return
            }
            switch operation() {
            case .registered:
                break
            case .invalid:
                issues.append(.invalid(slot: slot, combo: combo))
            case let .failed(status):
                issues.append(.unavailable(slot: slot, combo: combo, status: status))
            }
        }

        register(.voiceCapture, combo: settings.voiceCaptureCombo) {
            HotKeyCenter.shared.register(
                name: "voiceCapture", combo: settings.voiceCaptureCombo,
                released: { [weak self] in self?.handleVoiceTrigger(.released) }
            ) { [weak self] in self?.handleVoiceTrigger(.pressed) }
        }
        register(.capture, combo: settings.captureCombo) {
            HotKeyCenter.shared.register(name: "capture", combo: settings.captureCombo) { [weak self] in
                self?.captureSelection()
            }
        }
        register(.copy, combo: settings.copyCombo) {
            HotKeyCenter.shared.register(name: "copy", combo: settings.copyCombo) { [weak self] in
                self?.copyMarkdown()
            }
        }
        register(.stack, combo: settings.stackCombo) {
            HotKeyCenter.shared.register(name: "stack", combo: settings.stackCombo) { [weak self] in
                self?.showStack()
            }
        }
        register(.switchSession, combo: settings.switchSessionCombo) {
            HotKeyCenter.shared.register(name: "switchSession", combo: settings.switchSessionCombo) { [weak self] in
                self?.showQuickSwitcher()
            }
        }
        register(.clear, combo: settings.clearCombo) {
            HotKeyCenter.shared.register(name: "clear", combo: settings.clearCombo) { [weak self] in
                self?.clearStack()
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
        guard let sessionID = capturedSessionID(from: sender) else { NSSound.beep(); return }
        enqueueMenuMutation(.clearSession(sessionID: sessionID))
    }

    @objc private func undoClear() {
        guard store != nil else { NSSound.beep(); return }
        enqueueMenuMutation(.undoClear)
    }

    @objc private func switchToSession(_ sender: NSMenuItem) {
        guard let sessionID = capturedSessionID(from: sender) else { NSSound.beep(); return }
        enqueueMenuMutation(.switchSession(sessionID: sessionID))
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profileID = capturedSessionID(from: sender) else { NSSound.beep(); return }
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

    @objc private func newSession(_ sender: NSMenuItem) {
        guard let store else { NSSound.beep(); return }
        let sessions = store.sessions
        guard
            let draft = SessionDialogs.requestNewSessionName(sessions: sessions),
            let name = SessionDialogs.validateForEnqueue(
                draft,
                excluding: nil,
                sessions: store.sessions
            )
        else { return }
        enqueueMenuMutation(.createSession(Session(name: name)), presentsError: true)
    }

    @objc private func renameSession(_ sender: NSMenuItem) {
        guard let store, let sessionID = capturedSessionID(from: sender) else {
            NSSound.beep()
            return
        }
        let sessions = store.sessions
        guard
            let draft = SessionDialogs.requestRenamedSessionName(
                sessionID: sessionID,
                sessions: sessions
            ),
            let name = SessionDialogs.validateForEnqueue(
                draft,
                excluding: sessionID,
                sessions: store.sessions
            )
        else { return }
        enqueueMenuMutation(
            .renameSession(sessionID: sessionID, name: name),
            presentsError: true
        )
    }

    @objc private func deleteSession(_ sender: NSMenuItem) {
        guard let store, let sessionID = capturedSessionID(from: sender) else {
            NSSound.beep()
            return
        }
        let sessions = store.sessions
        guard SessionDialogs.confirmsDelete(
            sessionID: sessionID,
            sessions: sessions,
            lastCleared: store.lastCleared
        ) else { return }
        enqueueMenuMutation(.deleteSession(sessionID: sessionID), presentsError: true)
    }

    @objc private func retryPendingMutations() {
        guard let store else { NSSound.beep(); return }
        store.retryPendingMutations()
        exportController.send(.retry)
        refreshStatusItem()
    }

    private func capturedSessionID(from sender: NSMenuItem) -> UUID? {
        if let id = sender.representedObject as? UUID { return id }
        if let id = sender.representedObject as? NSUUID { return id as UUID }
        return nil
    }

    private func enqueueMenuMutation(
        _ mutation: SessionDocumentMutation,
        presentsError: Bool = false
    ) {
        guard let store else { NSSound.beep(); return }
        store.mutate(mutation) { [weak self] outcome in
            self?.refreshStatusItem()
            switch outcome {
            case let .rejected(message), let .commitFailed(message):
                NSSound.beep()
                if presentsError { SessionDialogs.showMessage(message) }
            case .committed, .noOp, .cancelled: break
            }
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
            },
            onRunSetup: { [weak self] in
                self?.presentSetup()
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
