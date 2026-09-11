import AppKit
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
        XCTAssertTrue(voice.ignoresMouseEvents)
        XCTAssertTrue(voice.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
    }

    func testPaletteAndSwitcherFactoriesKeepWindowInvariants() {
        let palette = StackPaletteWindowController.makePanel()
        XCTAssertTrue(palette.styleMask.contains([.borderless, .resizable]))
        XCTAssertTrue(palette.canBecomeKey)
        XCTAssertFalse(palette.ignoresMouseEvents)

        let switcher = StackSwitcherController.makePanel(model: StackSwitcherModel())
        XCTAssertTrue(switcher.styleMask.contains([.borderless, .nonactivatingPanel]))
        XCTAssertEqual(switcher.level, .floating)
        XCTAssertFalse(switcher.canBecomeKey)
        XCTAssertTrue(switcher.ignoresMouseEvents)
        XCTAssertTrue(switcher.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary]))
    }

    func testSettingsAndSetupFactoriesKeepWindowInvariants() {
        let settings = SettingsWindowController.makeWindowFrame()
        XCTAssertTrue(settings.styleMask.contains([.titled, .closable, .resizable, .fullSizeContentView]))
        XCTAssertTrue(settings.canBecomeKey)
        XCTAssertFalse(settings.ignoresMouseEvents)

        let setup = SetupWindowController.makeWindow()
        XCTAssertTrue(setup.styleMask.contains([.titled, .closable]))
        XCTAssertTrue(setup.canBecomeKey)

        let helper = AccessibilityHelperWindowController.makeWindow()
        XCTAssertTrue(helper.styleMask.contains([.titled, .closable]))
        XCTAssertTrue(helper.canBecomeKey)
    }
}
