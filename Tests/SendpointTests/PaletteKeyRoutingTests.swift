import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Sendpoint

/// Pins the single-fire key-routing contract: which keys the global monitor
/// declines for row-section `.onMoveCommand` ownership, and that every other
/// key stays monitor-owned in every focus state. Pure function over
/// responder-kind enums — no panels, fully deterministic.
final class PaletteKeyRoutingTests: XCTestCase {
    private func decline(
        _ key: PaletteKey,
        responder: PaletteResponderKind = .control,
        inlineEditActive: Bool = false,
        overlayOpen: Bool = false,
        cycling: Bool = false
    ) -> Bool {
        PaletteKeyRouting.shouldDeclineForRowFocus(
            key: key, responder: responder, inlineEditActive: inlineEditActive,
            overlayOpen: overlayOpen, cycling: cycling)
    }

    func testArrowsDeclineForRowFocusWhileBrowsing() {
        for key: PaletteKey in [.up, .down, .left, .right] {
            XCTAssertTrue(decline(key),
                "\(key) must decline so the focused row section owns it")
        }
    }

    func testTabNeverDeclinesInAnyFocusState() {
        // Narrower-and-safe subset: no view-side Tab owner exists
        // (.onMoveCommand covers arrows only), so Tab stays monitor-owned or
        // pane-toggle semantics would strand in the responder chain.
        for responder: PaletteResponderKind in [.text, .control, .none] {
            XCTAssertFalse(decline(.tab, responder: responder))
            XCTAssertFalse(decline(.backTab, responder: responder))
        }
    }

    func testReturnAndEscapeNeverDeclineInAnyFocusState() {
        // The monitor runs before the responder chain, so consuming there
        // guarantees a focused Button never also activates: no
        // select+perform double-fire, from any focus site.
        for responder: PaletteResponderKind in [.text, .control, .none] {
            XCTAssertFalse(decline(.activate, responder: responder))
            XCTAssertFalse(decline(.commandActivate, responder: responder))
            XCTAssertFalse(decline(.escape, responder: responder))
        }
    }

    func testCommandOptionAndDeleteKeysNeverDecline() {
        let keys: [PaletteKey] = [
            .optionUp, .optionDown, .commandDelete, .shiftCommandDelete,
            .commandDigit(2), .command("c"), .command("k"), .shiftCommand("c"),
        ]
        for key in keys {
            XCTAssertFalse(decline(key), "\(key) stays monitor-owned")
        }
    }

    func testTextOrMissingResponderNeverDeclinesEvenForArrows() {
        // Editing fields keep today's monitor behavior exactly; a nil
        // responder means focus is nowhere the row handlers can see.
        for responder: PaletteResponderKind in [.text, .none] {
            for key: PaletteKey in [.up, .down, .left, .right] {
                XCTAssertFalse(decline(key, responder: responder))
            }
        }
    }

    func testInlineEditOverlayAndCyclingForceMonitorOwnership() {
        for key: PaletteKey in [.up, .down, .left, .right] {
            XCTAssertFalse(decline(key, inlineEditActive: true),
                "inline-edit fall-through stays exactly as today")
            XCTAssertFalse(decline(key, overlayOpen: true),
                "overlay arrows stay monitor-owned")
            XCTAssertFalse(decline(key, cycling: true),
                "the cycling bypass stays total")
        }
    }

    // MARK: - PaletteKey decoding is unchanged

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
}
