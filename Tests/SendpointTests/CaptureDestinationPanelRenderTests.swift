import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class CaptureDestinationPanelRenderTests: XCTestCase {
    func testRetainedVoiceWindowDoesNotPresentTextCaptureDestinationPicker() async throws {
        let stack = Stack(name: "Default")
        let document = StackDocument(stacks: [stack], currentStackID: stack.id)
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

        // Load both retained view trees while their windows remain hidden.
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

    func testRenderPickerAboveLiveVoicePill() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce a manual review image.")
        }
        let stacks = [
            Stack(name: "Default", notes: [Note(subject: .standalone, body: "One")]),
            Stack(name: "Research", notes: [
                Note(subject: .standalone, body: "One"),
                Note(subject: .standalone, body: "Two"),
            ]),
            Stack(name: "Product notes"),
            Stack(name: "Follow-ups", notes: [Note(subject: .standalone, body: "One")]),
        ]
        let document = StackDocument(stacks: stacks, currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = makeController(store: store)
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
        voice.setContentSize(NSSize(width: 680, height: hosting.fittingSize.height))
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

        // Composite the actual hosting views at their live window coordinates.
        // This includes the real anchor placement, rather than a mock VStack.
        let bounds = voice.frame.union(picker.frame)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        for window in [voice, picker] {
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
        let url = URL(fileURLWithPath: directory)
            .appendingPathComponent("voice-capture-destination.png")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
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
                start: {}, stopAndTranscribe: { "" }, discard: {}, levelMeter: VoiceLevelMeter()
            ),
            surfaces: { _ in CaptureSurfaces(
                prepare: {}, show: { _ in }, focus: {}, stopEscapeHandling: {}, close: {}, discard: {}
            ) }
        )
        controller.configure(store: store)
        return controller
    }
}
