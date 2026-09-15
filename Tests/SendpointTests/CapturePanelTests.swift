import AppKit
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class CapturePanelTests: XCTestCase {
    func testCloseHandlerIsOneShot() {
        let panel = CapturePanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        var closeCount = 0
        panel.onClose = { closeCount += 1 }

        panel.performClose(nil)
        panel.performClose(nil)

        XCTAssertEqual(closeCount, 1)
        XCTAssertNil(panel.onClose)
    }

    func testCapturePanelFactoriesKeepWindowInvariants() {
        let editor = CaptureWindows.makeEditorPanel()
        XCTAssertTrue(editor.styleMask.contains([.titled, .closable, .resizable, .fullSizeContentView]))
        XCTAssertEqual(editor.level, .floating)
        XCTAssertTrue(editor.canBecomeKey)
        XCTAssertFalse(editor.ignoresMouseEvents)
        XCTAssertTrue(editor.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))

        let voice = CaptureWindows.makeVoicePanel()
        XCTAssertTrue(voice.styleMask.contains([.borderless, .nonactivatingPanel]))
        XCTAssertEqual(voice.level, .floating)
        XCTAssertTrue(voice.canBecomeKey)
        XCTAssertFalse(voice.ignoresMouseEvents)
        XCTAssertTrue(voice.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(voice.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
    }

    func testCaptureControlsAcceptTheFirstMouseClick() {
        let hosting = CaptureHostingView(rootView: EmptyView())
        XCTAssertTrue(hosting.acceptsFirstMouse(for: nil))
    }

    func testVoiceDestinationPanelLeavesEightPointsAbovePill() {
        let anchor = NSRect(x: 400, y: 90, width: 80, height: VoiceCaptureLayout.pillHeight)
        let visible = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let size = CaptureDestinationPanelLayout.panelSize(rowCount: 4)
        let origin = CaptureDestinationPanelLayout.panelOrigin(
            anchor: anchor, rowCount: 4, visibleFrame: visible
        )

        XCTAssertEqual(origin.x + size.width / 2, anchor.midX)
        XCTAssertEqual(
            origin.y + CaptureDestinationPanelLayout.shadowPadding,
            anchor.maxY + 8
        )
    }

    func testPaletteFactoryKeepsWindowInvariants() {
        let palette = StackPaletteWindowController.makePanel()
        XCTAssertTrue(palette.styleMask.contains([.borderless, .resizable, .nonactivatingPanel]))
        XCTAssertTrue(palette.canBecomeKey)
        XCTAssertFalse(palette.ignoresMouseEvents)
    }

    func testSettingsAndSetupFactoriesKeepWindowInvariants() {
        let settings = SettingsWindowController.makeWindowFrame()
        XCTAssertTrue(settings.styleMask.contains([.titled, .closable, .resizable, .fullSizeContentView]))
        XCTAssertTrue(settings.canBecomeKey)
        XCTAssertFalse(settings.ignoresMouseEvents)

        let setup = SetupWindowController.makeWindow()
        XCTAssertTrue(setup.styleMask.contains(.borderless))
        XCTAssertFalse(setup.styleMask.contains(.titled))
        XCTAssertFalse(setup.styleMask.contains(.resizable))
        XCTAssertEqual(setup.frame.size, SetupView.size)
        XCTAssertTrue(setup.canBecomeKey)
        XCTAssertFalse(setup.isOpaque)
        XCTAssertTrue(setup.hasShadow)
        XCTAssertFalse(setup.hidesOnDeactivate)
        XCTAssertFalse(setup.isFloatingPanel)
    }

    func testSetupHeroMotionSpeaksThenRests() {
        let speaking = SetupHeroMotion.phase(at: 1)
        XCTAssertEqual(speaking.mode, .live)
        XCTAssertGreaterThan(speaking.level, 0)

        let rest = SetupHeroMotion.phase(at: 5)
        XCTAssertEqual(rest.mode, .idle)
        XCTAssertEqual(rest.level, 0)

        let wrapped = SetupHeroMotion.phase(at: SetupHeroMotion.period + 1)
        XCTAssertEqual(wrapped.mode, .live)
    }

    func testSetupHeroStageWalksPermissionsInOrder() {
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .notGranted,
                microphone: .notDetermined,
                model: .notDownloaded
            ),
            .accessibility
        )
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .granted,
                microphone: .notDetermined,
                model: .notDownloaded
            ),
            .microphone
        )
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .granted,
                microphone: .denied,
                model: .notDownloaded
            ),
            .microphoneSettings
        )
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .granted,
                microphone: .granted,
                model: .notDownloaded
            ),
            .voiceModel
        )
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .granted,
                microphone: .granted,
                model: .downloading(progress: 0.4)
            ),
            .downloading(progress: 0.4)
        )
        XCTAssertEqual(
            SetupHeroStage.from(
                accessibility: .granted,
                microphone: .granted,
                model: .ready
            ),
            .ready
        )
        XCTAssertEqual(SetupHeroStage.accessibility.title, "Accessibility")
        XCTAssertEqual(SetupHeroStage.voiceModel.label, "Voice model")
        XCTAssertTrue(SetupHeroStage.voiceModel.showsDownloadGlyph)
        XCTAssertNil(SetupHeroStage.voiceModel.accessory)
        XCTAssertEqual(SetupHeroStage.downloading(progress: 0.4).accessory, "40%")
        XCTAssertTrue(SetupHeroStage.microphone.isActionable)
        XCTAssertFalse(SetupHeroStage.ready.isActionable)
        XCTAssertFalse(SetupHeroStage.downloading(progress: nil).isActionable)
        XCTAssertEqual(SetupHeroStage.voiceModel.step, SetupHeroStage.downloading(progress: 0.1).step)
        XCTAssertEqual(SetupHeroStage.accessibility.step, 0)
        XCTAssertEqual(SetupHeroStage.microphone.step, 1)
        XCTAssertEqual(SetupHeroStage.ready.step, 3)
    }
}
