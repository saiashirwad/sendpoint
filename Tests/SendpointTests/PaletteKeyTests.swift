import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

final class PaletteKeyTests: XCTestCase {
    private func keyEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(keyCode))!
    }

    func testArrowTabReturnAndEscapeDecoding() {
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_UpArrow)), .up)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_DownArrow)), .down)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_LeftArrow)), .left)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_RightArrow)), .right)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Tab)), .tab)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Tab, modifiers: .shift)), .backTab)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Return)), .activate)
        XCTAssertEqual(PaletteKey(event: keyEvent(keyCode: kVK_Escape)), .escape)
        XCTAssertEqual(
            PaletteKey(event: keyEvent(keyCode: kVK_UpArrow, modifiers: .option)), .optionUp)
        XCTAssertEqual(
            PaletteKey(event: keyEvent(keyCode: kVK_DownArrow, modifiers: .option)), .optionDown)
    }

    func testModifiedEditingArrowsAreNotClaimed() {
        for keyCode in [kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow] {
            for modifiers: NSEvent.ModifierFlags in [.shift, .command, .control, [.shift, .option]] {
                XCTAssertNil(PaletteKey(event: keyEvent(keyCode: keyCode, modifiers: modifiers)))
            }
        }
        for keyCode in [kVK_LeftArrow, kVK_RightArrow] {
            XCTAssertNil(PaletteKey(event: keyEvent(keyCode: keyCode, modifiers: .option)))
        }
    }
}
