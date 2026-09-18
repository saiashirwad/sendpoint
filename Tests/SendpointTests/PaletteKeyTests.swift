import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

@MainActor
final class PaletteKeyTests: XCTestCase {
    private func keyEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(keyCode))!
    }

    func testArrowReturnAndEscapeDecoding() {
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_UpArrow)), .up)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_DownArrow)), .down)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Return)), .activate)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Escape)), .escape)
        XCTAssertEqual(
            PaletteKey(event: keyEvent(keyCode: kVK_UpArrow, modifiers: .option)), .optionUp)
        XCTAssertEqual(
            PaletteKey(event: keyEvent(keyCode: kVK_DownArrow, modifiers: .option)), .optionDown)
    }

    func testShiftOnAStackShortcutDecodesAsAMoveToThatStack() {
        let suite = "PaletteKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = ShortcutSettings(defaults: defaults)
        let keys = [kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon]

        for (number, key) in zip(1..., keys) {
            let deviceDependentFlags: UInt = 0x120
            let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags([.option, .shift]).rawValue | deviceDependentFlags)
            XCTAssertEqual(
                PaletteKey(event: keyEvent(keyCode: key, modifiers: flags), shortcuts: shortcuts),
                .moveToStack(number)
            )
            XCTAssertNil(PaletteKey(event: keyEvent(keyCode: key, modifiers: .option), shortcuts: shortcuts))
            XCTAssertNil(PaletteKey(event: keyEvent(keyCode: key, modifiers: .shift), shortcuts: shortcuts))
        }
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_UpArrow), shortcuts: shortcuts), .up)
    }

    func testModifiedEditingArrowsAreNotClaimed() {
        for keyCode in [kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow] {
            for modifiers: NSEvent.ModifierFlags in [.shift, .command, .control, [.shift, .option]] {
                XCTAssertNil(PaletteKey(event: keyEvent(keyCode: keyCode, modifiers: modifiers)))
            }
        }
        for keyCode in [kVK_LeftArrow, kVK_RightArrow, kVK_Tab] {
            XCTAssertNil(PaletteKey(event: keyEvent(keyCode: keyCode)))
            XCTAssertNil(PaletteKey(event: keyEvent(keyCode: keyCode, modifiers: .option)))
        }
        XCTAssertNil(PaletteKey(event: keyEvent(keyCode: kVK_Return, modifiers: .command)))
    }
}
