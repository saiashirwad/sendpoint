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

    func testVoicePanelSizeFollowsTheCaptionsSetting() {
        let pill = VoiceCaptureLayout.panelSize(card: false, lines: 4, fontSize: 13)
        XCTAssertEqual(pill.width, VoiceCaptureLayout.panelWidth)
        XCTAssertEqual(pill.height, VoiceCaptureLayout.pillHeight + VoiceCaptureLayout.shadowPadding * 2)

        let card = VoiceCaptureLayout.panelSize(card: true, lines: 4, fontSize: 13)
        XCTAssertEqual(card.width, pill.width, "one window, one width: the picker margin stays")
        XCTAssertEqual(
            card.height,
            VoiceCaptureLayout.cardHeight(lines: 4, fontSize: 13) + VoiceCaptureLayout.shadowPadding * 2
        )
        XCTAssertGreaterThan(
            VoiceCaptureLayout.cardHeight(lines: 5, fontSize: 16),
            VoiceCaptureLayout.cardHeight(lines: 2, fontSize: 11)
        )
        XCTAssertEqual(
            VoiceCaptureLayout.cardHeight(lines: 99, fontSize: 13),
            VoiceCaptureLayout.cardHeight(lines: VoiceSettings.previewLinesMax, fontSize: 13),
            "the card never grows past the settings ceiling"
        )
    }

    func testCardAnchorReachesTheCardTop() {
        // The footer's bottom edge sits one bottom padding above the card's
        // bottom, so an anchor of this height ends exactly at the card's top.
        let anchor = VoiceCaptureLayout.cardAnchorHeight(lines: 3, fontSize: 13)
        XCTAssertEqual(
            anchor + VoiceCaptureLayout.cardPaddingBottom,
            VoiceCaptureLayout.cardHeight(lines: 3, fontSize: 13)
        )
        XCTAssertGreaterThan(anchor, VoiceCaptureLayout.cardFooterHeight)
    }

    func testTranscriptWindowKeepsRowIdentityWhileScrolling() {
        let lines = ["one", "two", "three", "four", "five"]
        let window = LiveTranscriptPreview.window(lines, max: 3)
        XCTAssertEqual(window.rows.map(\.id), [2, 3, 4])
        XCTAssertEqual(window.rows.map(\.text), ["three", "four", "five"])
        XCTAssertTrue(window.overflow)

        let short = LiveTranscriptPreview.window(["one"], max: 3)
        XCTAssertEqual(short.rows.map(\.id), [0])
        XCTAssertFalse(short.overflow)
        XCTAssertTrue(LiveTranscriptPreview.window([], max: 3).rows.isEmpty)
    }

    func testTetherNamesTheSelection() {
        XCTAssertNil(VoiceOverlayCopy.tether(for: "  \n"))
        XCTAssertEqual(VoiceOverlayCopy.tether(for: "one"), "1 word selected")
        XCTAssertEqual(VoiceOverlayCopy.tether(for: "a short  selected\npassage"), "4 words selected")
    }

    func testPaletteFactoryKeepsWindowInvariants() {
        let palette = StackPaletteWindowController.makePanel()
        XCTAssertTrue(palette.styleMask.contains([.titled, .fullSizeContentView, .resizable, .nonactivatingPanel]))
        XCTAssertTrue(palette.isOpaque, "an opaque backing keeps text smoothing on")
        XCTAssertEqual(palette.titleVisibility, .hidden)
        XCTAssertTrue(palette.standardWindowButton(.closeButton)?.isHidden ?? false)
        XCTAssertTrue(palette.canBecomeKey)
        XCTAssertFalse(palette.ignoresMouseEvents)
        XCTAssertTrue(palette.isMovable)
        XCTAssertFalse(palette.isMovableByWindowBackground)
        XCTAssertTrue(palette.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(palette.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testSettingsAndSetupFactoriesKeepWindowInvariants() {
        let settings = SettingsWindowController.makeWindowFrame()
        XCTAssertTrue(settings.styleMask.contains([.titled, .closable, .resizable, .fullSizeContentView]))
        XCTAssertEqual(settings.title, "Sendpoint")
        XCTAssertTrue(settings.canBecomeKey)
        XCTAssertFalse(settings.ignoresMouseEvents)
        XCTAssertTrue(settings.isMovable)
        XCTAssertFalse(settings.isMovableByWindowBackground)
        XCTAssertTrue(settings.collectionBehavior.contains(.moveToActiveSpace))

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
        XCTAssertTrue(setup.collectionBehavior.contains(.moveToActiveSpace))
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
