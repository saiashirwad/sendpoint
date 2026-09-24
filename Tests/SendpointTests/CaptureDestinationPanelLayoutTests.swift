import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class CaptureDestinationPanelLayoutTests: XCTestCase {
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

    func testPickerSitsAboveLiveVoicePill() async throws {
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
        let defaults = UserDefaults(suiteName: "CaptureDestinationPanelLayoutTests.\(UUID().uuidString)")!
        let permissions = PermissionController(services: PermissionServices(
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
