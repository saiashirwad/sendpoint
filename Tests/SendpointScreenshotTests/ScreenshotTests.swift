import AppKit
import SendpointDomain
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class ScreenshotTests: XCTestCase {
    private var directory = ""
    private var appearance = "light"
    private var record = SnapshotTestingConfiguration.Record.all
    private var suites: [String] = []

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SENDPOINT_SHOTS_DIR"] else {
            throw XCTSkip("Run ./shots.sh to render every screen.")
        }
        self.directory = directory
        appearance = environment["SENDPOINT_SHOTS_APPEARANCE"] ?? "light"
        record = environment["SENDPOINT_SHOTS_RECORD"] == "missing" ? .missing : .all
        NSApplication.shared.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        Self.registerAppFonts()
    }

    override func tearDown() async throws {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    // MARK: - Text capture

    func testTextCapture() async throws {
        let stacks = [Stack(notes: [note(subject: .standalone, body: "One")])]
        let store = try await makeStore(stacks)
        let controller = makeCaptureController(store: store)
        let context = NoteCaptureContext(stackID: stacks[0].id)
        controller.send(.begin(.text, context))
        controller.send(.selection(context, CapturedSelection(text: "A short selected passage")))
        let editor = CaptureWindows.makeEditorPanel(contentView: CaptureHostingView(
            rootView: CaptureView(model: controller)
        ))
        editor.setContentSize(VoiceCaptureLayout.cardSize(
            lines: controller.transcriptionPreviewLines,
            fontSize: CGFloat(controller.transcriptionPreviewFontSize)
        ))
        defer {
            controller.send(.teardown)
            editor.contentView = nil
            editor.close()
            store.teardown()
        }
        try await show([editor])
        try shoot([editor], "text-capture-empty")

        let typed = try XCTUnwrap(Self.textView(in: try XCTUnwrap(editor.contentView)))
        editor.makeFirstResponder(typed)
        typed.insertText("Follow up on this before the review.", replacementRange: typed.selectedRange())
        try await settle()
        try shoot([editor], "text-capture-typed")

        controller.send(.toggleDestinations(context))
        try await settle()
        try shoot([editor] + (editor.childWindows ?? []), "text-capture-destination")
    }

    // MARK: - Voice capture

    func testVoiceCapturePill() async throws {
        let (controller, voice, context, teardown) = try await makeVoice(captions: false)
        defer { teardown() }
        try shoot([voice], "voice-pill-recording")

        controller.send(.toggleDestinations(context))
        try await settle()
        try shoot([voice] + (voice.childWindows ?? []), "voice-pill-destination")
        controller.send(.dismissDestinations(context))

        controller.send(.finishVoice)
        try await settle()
        try shoot([voice], "voice-pill-transcribing")
    }

    func testVoiceCaptureCard() async throws {
        let (controller, voice, context, teardown) = try await makeVoice(captions: true)
        defer { teardown() }
        controller.send(.voicePartial(
            context,
            "So this is what it looks like, testing, testing, and the words keep arriving "
                + "while the card stays put at the foot of the screen."
        ))
        try await settle()
        try shoot([voice], "voice-card-recording")

        controller.send(.toggleDestinations(context))
        try await settle()
        try shoot([voice] + (voice.childWindows ?? []), "voice-card-destination")
        controller.send(.dismissDestinations(context))

        controller.send(.failed(context, "The microphone stopped responding."))
        try await settle()
        try shoot([voice], "voice-card-failed")
    }

    // MARK: - Stack palette

    func testStackPalette() async throws {
        let quoted = [
            note(subject: .selection(quote: "A short passage."), body: "This is a sound test. I'm just testing this out."),
            note(
                subject: .selection(quote: String(repeating: "The library lends more books than it owns, and the ledger never balances. ", count: 4)),
                body: "Another sound test. Why would you want another sound test?"
            ),
            note(subject: .standalone, body: "Check the export copy before sending."),
        ]
        let many = (1...12).map { note(subject: .standalone, body: "Note \($0)") }
        let stacks = filled([Stack(notes: quoted), Stack(), Stack(notes: many)])
        let store = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: stacks, currentStackID: stacks[0].id) }, commit: { _ in }
        ))
        let defaults = makeDefaults()
        let model = StackPaletteController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults),
            export: ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in true })),
            onSelectTemplate: { _ in }
        )
        let panel = StackPaletteWindowController.makePanel()
        let hosting = NSHostingView(rootView: StackPaletteView(model: model, noteFrames: NoteFrames()))
        hosting.sizingOptions = []
        panel.contentView = hosting
        defer {
            model.send(.teardown)
            panel.contentView = nil
            panel.close()
            store.teardown()
        }
        model.send(.open)
        try await show([panel])

        for (index, name) in ["notes", "empty", "long"].enumerated() {
            store.mutate(.switchStack(stackID: stacks[index].id))
            await store.waitForIdle()
            model.send(.documentChanged)
            try await settle()
            try shoot([panel], "stack-\(name)")
        }
        store.mutate(.switchStack(stackID: stacks[0].id))
        await store.waitForIdle()
        model.send(.documentChanged)
        model.send(.query("sound"))
        try await settle()
        try shoot([panel], "stack-search")
        model.send(.query(""))

        model.send(.toggleOverlay(.templates))
        try await settle()
        try shoot([panel], "stack-templates")
        model.send(.closeOverlay)
        model.send(.toggleOverlay(.actions))
        try await settle()
        try shoot([panel], "stack-actions")
    }

    func testStackReadout() async throws {
        let stacks = [Stack(notes: [note(subject: .standalone, body: "One")]), Stack()]
        let store = try await makeStore(stacks)
        let controller = StackReadoutController(store: store)
        defer {
            controller.teardown()
            store.teardown()
        }
        controller.show(number: 1)
        try await show([controller.panel])
        try shoot([controller.panel], "stack-readout")
    }

    // MARK: - Latest note

    func testLatestNoteEditor() async throws {
        let stacks = [Stack(notes: [note(
            subject: .selection(quote: "A capture should preserve the thought, not interrupt it."),
            body: "Keep the editor focused on this note.\n\nThe original quote should stay attached."
        )])]
        let store = try await makeStore(stacks)
        let model = LatestNoteEditor(store: store)
        let window = LatestNoteEditorWindow(model: model, surfaces: SurfaceCoordinator(setRegularActivation: { _ in }))
        defer {
            window.teardown()
            store.teardown()
        }
        model.send(.open)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Edit latest note" && $0.isVisible })
        try await show([panel])
        try shoot([panel], "latest-note")

        let text = try XCTUnwrap(Self.textView(in: try XCTUnwrap(panel.contentView)))
        text.insertText("\n\nAn unsaved change.", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        panel.performClose(nil)
        try await settle()
        try shoot([panel], "latest-note-discard")
        model.send(.keepEditing)
    }

    func testLatestNoteStandaloneAndSaveFailed() async throws {
        struct Refused: LocalizedError { var errorDescription: String? { "The disk is full." } }
        let stacks = filled([Stack(notes: [note(subject: .standalone, body: "Ship the export fix on Friday.")])])
        let store = try await StackStore(persistence: StorePersistence(
            load: { StackDocument(stacks: stacks, currentStackID: stacks[0].id) }, commit: { _ in throw Refused() }
        ))
        let model = LatestNoteEditor(store: store)
        let window = LatestNoteEditorWindow(model: model, surfaces: SurfaceCoordinator(setRegularActivation: { _ in }))
        defer {
            window.teardown()
            store.teardown()
        }
        model.send(.open)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "Edit latest note" && $0.isVisible })
        try await show([panel])
        try shoot([panel], "latest-note-standalone")

        let text = try XCTUnwrap(Self.textView(in: try XCTUnwrap(panel.contentView)))
        text.insertText(" And the copy.", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        )))
        await store.waitForIdle()
        try await settle()
        try shoot([panel], "latest-note-save-failed")
    }

    // MARK: - Setup

    func testSetup() async throws {
        struct Stage {
            let name: String
            var accessibility = AccessibilityPermissionState.granted
            var microphone = MicrophonePermissionState.granted
            var modelExists = false
            var download: (@Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)?
            var tourStep: Int?
        }
        struct Failed: LocalizedError { var errorDescription: String? { "The download stopped." } }
        let stages = [
            Stage(name: "accessibility", accessibility: .notGranted, microphone: .notDetermined),
            Stage(name: "microphone", microphone: .notDetermined),
            Stage(name: "microphone-denied", microphone: .denied),
            Stage(name: "voice-model"),
            Stage(name: "downloading", download: { report in
                report(0.42)
                try await Task.sleep(for: .seconds(60))
            }),
            Stage(name: "download-failed", download: { _ in throw Failed() }),
            Stage(name: "tour-voice", modelExists: true, tourStep: 0),
            Stage(name: "tour-text", modelExists: true, tourStep: 1),
            Stage(name: "tour-send", modelExists: true, tourStep: 2),
        ]
        for stage in stages {
            let defaults = makeDefaults()
            let permissions = PermissionController(services: PermissionServices(
                accessibilityStatus: { stage.accessibility }, requestAccessibility: { true },
                microphoneStatus: { stage.microphone }, requestMicrophone: { true },
                voiceModelFilesExist: { stage.modelExists },
                downloadVoiceModel: { report in try await stage.download?(report) },
                openAccessibilitySettings: {}, openMicrophoneSettings: {}
            ))
            if stage.download != nil { permissions.downloadModel() }
            let tour = SetupTour()
            for _ in 0..<(stage.tourStep ?? 0) { tour.send(.skip) }
            let window = makeWindow(size: SetupView.size, content: SetupView(
                settings: AppSettings(defaults: defaults), permissionState: permissions, tour: tour,
                shortcuts: ShortcutSettings(defaults: defaults), voiceSettings: VoiceSettings(defaults: defaults),
                onComplete: {}, onDismiss: {}
            ))
            try await show([window])
            try shoot([window], "setup-\(stage.name)")
            window.contentView = nil
            window.close()
            permissions.teardown()
        }
    }

    // MARK: - Settings

    func testSettings() async throws {
        let stacks = [Stack(notes: [note(subject: .standalone, body: "One")]), Stack()]
        let store = try await makeStore(stacks)
        defer { store.teardown() }
        for tab in SettingsTab.allCases {
            let defaults = makeDefaults()
            let shortcuts = ShortcutSettings(defaults: defaults)
            let handle = SettingsStoreHandle()
            handle.store = store
            let templates = TemplateSettings(defaults: defaults)
            let controller = makeCaptureController(store: store, defaults: defaults)
            let window = makeWindow(size: SettingsView.size, content: SettingsView(
                settings: AppSettings(defaults: defaults), shortcuts: shortcuts,
                voiceSettings: VoiceSettings(defaults: defaults),
                hotKeyRegistrar: HotKeyRegistrar(settings: shortcuts, center: HotKeyCenter(
                    registerEvent: { _, _, _ in (noErr, nil) }, unregisterEvent: { _ in }
                )),
                captureController: controller,
                templateEditor: TemplateEditorController(settings: templates),
                permissionState: makePermissions(), storeHandle: handle,
                onSelectTemplate: { _ in }, onSettingsChanged: {}, onCheckForUpdates: {}, onShowStack: {},
                tab: tab
            ))
            try await show([window])
            try shoot([window], "settings-\(tab.rawValue)")
            controller.send(.teardown)
            window.contentView = nil
            window.close()
        }
    }

    // MARK: - Fixtures

    private func makeVoice(captions: Bool) async throws
        -> (CaptureController, NSPanel, NoteCaptureContext, () -> Void) {
        let stacks = [Stack(notes: [note(subject: .standalone, body: "One"), note(subject: .standalone, body: "Two")]), Stack()]
        let store = try await makeStore(stacks)
        let controller = makeCaptureController(store: store)
        controller.setTranscriptionPreview(captions)
        let context = NoteCaptureContext(stackID: stacks[0].id)
        controller.send(.begin(.voice, context))
        controller.send(.recordingStarted(context))
        controller.send(.selection(context, CapturedSelection(text: "A short selected passage")))
        let voice = CaptureWindows.makeVoicePanel(contentView: CaptureHostingView(
            rootView: VoiceCaptureView(model: controller, meter: controller.levelMeter)
        ))
        voice.setContentSize(VoiceCaptureLayout.panelSize(
            card: captions, lines: controller.transcriptionPreviewLines,
            fontSize: CGFloat(controller.transcriptionPreviewFontSize)
        ))
        try await show([voice])
        return (controller, voice, context, {
            controller.send(.teardown)
            voice.contentView = nil
            voice.close()
            store.teardown()
        })
    }

    private func makeStore(_ leading: [Stack]) async throws -> StackStore {
        let document = StackDocument(stacks: filled(leading), currentStackID: leading[0].id)
        return try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ScreenshotTests.\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func makePermissions() -> PermissionController {
        PermissionController(services: PermissionServices(
            accessibilityStatus: { .granted }, requestAccessibility: { true },
            microphoneStatus: { .granted }, requestMicrophone: { true },
            voiceModelFilesExist: { true }, downloadVoiceModel: { _ in },
            openAccessibilitySettings: {}, openMicrophoneSettings: {}
        ))
    }

    private func makeCaptureController(store: StackStore, defaults: UserDefaults? = nil) -> CaptureController {
        let defaults = defaults ?? makeDefaults()
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults),
            voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: makePermissions(),
            selection: SelectionCapture(read: { _, _ in CapturedSelection(text: "") }, paste: { _, _ in false }),
            recorder: VoiceRecorder(start: { _ in }, stop: { _ in }, discard: {}, levelMeter: VoiceLevelMeter()),
            surfaces: { _ in CaptureSurfaces(prepare: {}, show: { _ in }, focus: {}, close: {}, discard: {}) }
        )
        controller.configure(store: store)
        return controller
    }

    private func makeWindow(size: CGSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content.background(Color(nsColor: Ink.nsPaper)))
        return window
    }

    // MARK: - Rendering

    private func show(_ windows: [NSWindow]) async throws {
        for window in windows {
            window.appearance = NSApp.appearance
            window.alphaValue = 0
            window.setFrameOrigin(NSPoint(x: 240, y: 240))
            window.orderFrontRegardless()
        }
        try await settle()
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(350))
        for window in NSApp.windows { window.alphaValue = 0 }
    }

    private func shoot(_ windows: [NSWindow], _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try Self.composite(windows)
        let failure = verifySnapshot(
            of: image, as: .image(precision: 0.995), named: "\(name)-\(appearance)",
            record: record, snapshotDirectory: directory, file: file, testName: "sendpoint", line: line
        )
        if let failure, record == .missing { XCTFail(failure, file: file, line: line) }
    }

    private static func composite(_ windows: [NSWindow]) throws -> NSImage {
        let visible = windows.filter(\.isVisible)
        let bounds = visible.dropFirst().map(\.frame).reduce(visible[0].frame) { $0.union($1) }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        (NSApp.appearance?.bestMatch(from: [.darkAqua]) == nil ? NSColor.white : NSColor.black).setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        for window in visible {
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let layer = NSImage(size: view.bounds.size)
            layer.addRepresentation(bitmap)
            layer.draw(in: NSRect(
                x: window.frame.minX - bounds.minX, y: window.frame.minY - bounds.minY,
                width: view.bounds.width, height: view.bounds.height
            ), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        return image
    }

    private static func textView(in view: NSView) -> NSTextView? {
        if let found = view as? NSTextView { return found }
        for sub in view.subviews { if let found = textView(in: sub) { return found } }
        return nil
    }

    private static let fontsRegistered: Void = {
        let fonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        let files = (try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? []
        CTFontManagerRegisterFontURLs(files as CFArray, .process, true, nil)
    }()

    private static func registerAppFonts() { _ = fontsRegistered }
}

private func note(subject: Subject, body: String) -> Note {
    Note(subject: subject, body: body, createdAt: Date(timeIntervalSinceReferenceDate: 780_000_000))
}

private func filled(_ leading: [Stack]) -> [Stack] {
    leading + (leading.count..<StackDocument.stackCount).map { _ in Stack() }
}
