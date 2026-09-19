import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class CaptureDestinationPanelRenderTests: XCTestCase {
    func testRetainedVoiceWindowDoesNotPresentTextCaptureDestinationPicker() async throws {
        let stack = Stack()
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        let voice = CaptureWindows.makeVoicePanel(contentView: CaptureHostingView(
            rootView: VoiceCaptureView(model: controller, meter: controller.levelMeter)
        ))
        let editor = CaptureWindows.makeEditorPanel(contentView: CaptureHostingView(
            rootView: CaptureView(model: controller)
        ))
        defer {
            controller.send(.teardown)
            for panel in [voice, editor] {
                panel.contentView = nil
                panel.close()
            }
        }

        for panel in [voice, editor] { panel.contentView?.layoutSubtreeIfNeeded() }
        let textContext = NoteCaptureContext(stackID: stack.id)
        controller.send(.begin(.text, textContext))
        controller.send(.selection(textContext, CapturedSelection(text: "Selected text")))
        controller.send(.toggleDestinations(textContext))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(controller.state.session?.destinationPicker, .open)
        XCTAssertTrue(voice.childWindows?.isEmpty ?? true,
                      "A text capture must not open a picker on the retained voice window")

        controller.send(.dismiss)
        let voiceContext = NoteCaptureContext(stackID: stack.id)
        controller.send(.begin(.voice, voiceContext))
        controller.send(.recordingStarted(voiceContext))
        controller.send(.selection(voiceContext, CapturedSelection(text: "Selected text")))
        try await Task.sleep(for: .milliseconds(150))
        controller.send(.toggleDestinations(voiceContext))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(voice.childWindows?.filter(\.isVisible).count, 1)

        controller.send(.cancelVoice)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(voice.childWindows?.isEmpty ?? true,
                      "Ending capture must remove the destination panel")
    }

    func testBeginningATextCaptureFocusesTheNoteWithNoScrollInset() async throws {
        let stack = Stack()
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        let editor = CaptureWindows.makeEditorPanel(contentView: CaptureHostingView(
            rootView: CaptureView(model: controller)
        ))
        defer {
            controller.send(.teardown)
            editor.contentView = nil
            editor.close()
        }
        editor.contentView?.layoutSubtreeIfNeeded()
        controller.send(.begin(.text, NoteCaptureContext(stackID: stack.id)))
        try await Task.sleep(for: .milliseconds(150))

        let note = try XCTUnwrap(editor.firstResponder as? NoteTextView)
        let scroll = try XCTUnwrap(note.enclosingScrollView)
        XCTAssertFalse(scroll.automaticallyAdjustsContentInsets)
        XCTAssertEqual(scroll.contentInsets.top, 0)
        XCTAssertEqual(note.convert(note.textContainerOrigin, to: scroll), .zero,
                       "the titlebar must not push the note below the top of its editor")

        note.insertText("Follow up", replacementRange: note.selectedRange())
        XCTAssertEqual(controller.note, "Follow up")
    }

    func testRenderPickerAboveLiveVoicePill() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce a manual review image.")
        }
        let stacks = [
            Stack(notes: [Note(subject: .standalone, body: "One")]),
            Stack(notes: [
                Note(subject: .standalone, body: "One"),
                Note(subject: .standalone, body: "Two"),
            ]),
            Stack(),
            Stack(notes: [Note(subject: .standalone, body: "One")]),
        ]
        let document = StackDocument(stacks: filled(stacks), currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        controller.setTranscriptionPreview(false)
        let context = NoteCaptureContext(stackID: stacks[0].id)
        controller.send(.begin(.voice, context))
        controller.send(.recordingStarted(context))
        controller.send(.selection(context, CapturedSelection(text: "A short selected passage")))
        controller.send(.toggleDestinations(context))
        controller.chooseDestination(stacks[1].id, context: context)
        controller.send(.toggleDestinations(context))

        controller.send(.dismissDestinations(context))
        let hosting = CaptureHostingView(rootView: VoiceCaptureView(
            model: controller, meter: controller.levelMeter
        ))
        let voice = CaptureWindows.makeVoicePanel(contentView: hosting)
        voice.setContentSize(VoiceCaptureLayout.panelSize(card: false, lines: 4, fontSize: 13))
        voice.setFrameOrigin(NSPoint(x: 400, y: 160))
        defer {
            controller.send(.teardown)
            voice.contentView = nil
            voice.close()
        }
        voice.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        controller.send(.toggleDestinations(context))
        try await Task.sleep(for: .milliseconds(200))
        let picker = try XCTUnwrap(voice.childWindows?.first)
        let pillTop = voice.frame.minY + VoiceCaptureLayout.shadowPadding
            + VoiceCaptureLayout.pillHeight
        XCTAssertEqual(
            picker.frame.minY + CaptureDestinationPanelLayout.shadowPadding - pillTop,
            8, accuracy: 0.5
        )

        try composite([voice, picker], to: directory, name: "voice-capture-destination.png")
    }

    func testRenderLiveVoiceCard() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce a manual review image.")
        }
        let stacks = [
            Stack(notes: [
                Note(subject: .standalone, body: "One"),
                Note(subject: .standalone, body: "Two"),
            ]),
        ]
        let document = StackDocument(stacks: filled(stacks), currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        controller.setTranscriptionPreview(true)
        let lines = controller.transcriptionPreviewLines
        let fontSize = CGFloat(controller.transcriptionPreviewFontSize)
        let context = NoteCaptureContext(stackID: stacks[0].id)
        controller.send(.begin(.voice, context))
        controller.send(.recordingStarted(context))
        controller.send(.selection(context, CapturedSelection(text: "A short selected passage")))
        controller.send(.voicePartial(
            context,
            "So this is what it looks like, testing, testing, testing, testing, testing, "
                + "and the words keep arriving while the card stays put at the foot of the screen."
        ))
        let hosting = CaptureHostingView(rootView: VoiceCaptureView(
            model: controller, meter: controller.levelMeter
        ))
        let voice = CaptureWindows.makeVoicePanel(contentView: hosting)
        voice.setContentSize(VoiceCaptureLayout.panelSize(card: true, lines: lines, fontSize: fontSize))
        voice.setFrameOrigin(NSPoint(x: 400, y: 160))
        defer {
            controller.send(.teardown)
            voice.contentView = nil
            voice.close()
        }
        voice.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        try composite([voice], to: directory, name: "voice-capture-card.png")

        controller.send(.toggleDestinations(context))
        try await Task.sleep(for: .milliseconds(200))
        let picker = try XCTUnwrap(voice.childWindows?.first)
        try composite([voice, picker], to: directory, name: "voice-capture-card-destination.png")
    }

    func testRenderTextCaptureCard() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce a manual review image.")
        }
        let stacks = [Stack(notes: [Note(subject: .standalone, body: "One")])]
        let document = StackDocument(stacks: filled(stacks), currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        let context = NoteCaptureContext(stackID: stacks[0].id)
        controller.send(.begin(.text, context))
        controller.send(.selection(context, CapturedSelection(text: "A short selected passage")))
        try registerAppFonts()
        controller.stepTranscriptionPreviewLines(bySteps: 5 - controller.transcriptionPreviewLines)
        controller.stepTranscriptionPreviewFontSize(bySteps: 15 - controller.transcriptionPreviewFontSize)
        let editor = CaptureWindows.makeEditorPanel(contentView: CaptureHostingView(
            rootView: CaptureView(model: controller)
        ))
        editor.setContentSize(VoiceCaptureLayout.cardSize(
            lines: controller.transcriptionPreviewLines,
            fontSize: CGFloat(controller.transcriptionPreviewFontSize)
        ))
        editor.setFrameOrigin(NSPoint(x: 400, y: 160))
        defer {
            controller.send(.teardown)
            editor.contentView = nil
            editor.close()
        }
        editor.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        try screenshot(editor, to: directory, name: "text-capture-card-empty.png")
        func textView(in view: NSView) -> NSTextView? {
            if let found = view as? NSTextView { return found }
            for sub in view.subviews { if let found = textView(in: sub) { return found } }
            return nil
        }
        let typed = try XCTUnwrap(textView(in: try XCTUnwrap(editor.contentView)))
        editor.makeFirstResponder(typed)
        typed.insertText("Follow up on this before the review.", replacementRange: typed.selectedRange())
        try await Task.sleep(for: .milliseconds(300))
        try screenshot(editor, to: directory, name: "text-capture-card.png")
    }

    private func registerAppFonts() throws {
        let fonts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        let files = try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)
        CTFontManagerRegisterFontURLs(files as CFArray, .process, true, nil)
    }

    private func screenshot(_ window: NSWindow, to directory: String, name: String) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", directory + "/" + name]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
    }

    private func composite(_ windows: [NSWindow], to directory: String, name: String) throws {
        let bounds = windows.map(\.frame).reduce(windows[0].frame) { $0.union($1) }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        for window in windows {
            let view = try XCTUnwrap(window.contentView)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let layer = NSImage(size: view.bounds.size)
            layer.addRepresentation(bitmap)
            layer.draw(in: NSRect(
                x: window.frame.minX - bounds.minX,
                y: window.frame.minY - bounds.minY,
                width: window.frame.width, height: window.frame.height
            ), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func testPickerClearsTheWholeCardWhenCaptionsAreOn() async throws {
        let stack = Stack()
        let document = StackDocument(stacks: filled([stack]), currentStackID: stack.id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
        controller.setTranscriptionPreview(true)
        controller.stepTranscriptionPreviewLines(bySteps: 3 - controller.transcriptionPreviewLines)
        let lines = controller.transcriptionPreviewLines
        let fontSize = CGFloat(controller.transcriptionPreviewFontSize)
        let hosting = CaptureHostingView(rootView: VoiceCaptureView(
            model: controller, meter: controller.levelMeter
        ))
        let voice = CaptureWindows.makeVoicePanel(contentView: hosting)
        voice.setContentSize(VoiceCaptureLayout.panelSize(card: true, lines: lines, fontSize: fontSize))
        voice.setFrameOrigin(NSPoint(x: 400, y: 160))
        defer {
            controller.send(.teardown)
            voice.contentView = nil
            voice.close()
        }
        let context = NoteCaptureContext(stackID: stack.id)
        controller.send(.begin(.voice, context))
        controller.send(.recordingStarted(context))
        voice.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(300))
        controller.send(.toggleDestinations(context))
        try await Task.sleep(for: .milliseconds(200))

        let picker = try XCTUnwrap(voice.childWindows?.first)
        let cardTop = voice.frame.minY + VoiceCaptureLayout.shadowPadding
            + VoiceCaptureLayout.cardHeight(lines: lines, fontSize: fontSize)
        XCTAssertEqual(
            picker.frame.minY + CaptureDestinationPanelLayout.shadowPadding - cardTop,
            CaptureDestinationPanelLayout.anchorGap, accuracy: 0.5,
            "The picker must sit above the transcript, not over it"
        )
    }

    private func makeController(store: StackStore) -> CaptureController {
        let defaults = UserDefaults(suiteName: "CaptureDestinationPanelRenderTests.\(UUID().uuidString)")!
        let permissions = PermissionState(services: PermissionServices(
            accessibilityStatus: { .granted }, requestAccessibility: { true },
            microphoneStatus: { .granted }, requestMicrophone: { true },
            voiceModelFilesExist: { true }, downloadVoiceModel: { _ in },
            openAccessibilitySettings: {}, openMicrophoneSettings: {}
        ))
        let controller = CaptureController(
            settings: AppSettings(defaults: defaults),
            voiceSettings: VoiceSettings(defaults: defaults),
            permissionState: permissions,
            selection: SelectionCapture(
                read: { _, _ in CapturedSelection(text: "") }, paste: { _, _ in false }
            ),
            recorder: VoiceRecorder(
                start: { _ in }, stop: { _ in }, discard: {}, levelMeter: VoiceLevelMeter()
            ),
            surfaces: { _ in CaptureSurfaces(
                prepare: {}, show: { _ in }, focus: {}, close: {}, discard: {}
            ) }
        )
        controller.configure(store: store)
        return controller
    }
}
