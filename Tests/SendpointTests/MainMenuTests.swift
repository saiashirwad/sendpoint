import AppKit
import XCTest
@testable import Sendpoint

@MainActor
final class MainMenuTests: XCTestCase {
    func testEditMenuInstallsStandardResponderActions() throws {
        let menu = MainMenu.build()
        let edit = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })

        assertItem(edit, title: "Undo", key: "z", action: Selector(("undo:")))
        assertItem(edit, title: "Cut", key: "x", action: #selector(NSText.cut(_:)))
        assertItem(edit, title: "Copy", key: "c", action: #selector(NSText.copy(_:)))
        assertItem(edit, title: "Paste", key: "v", action: #selector(NSText.paste(_:)))
        assertItem(edit, title: "Select All", key: "a", action: #selector(NSText.selectAll(_:)))
    }

    private func assertItem(_ menu: NSMenu, title: String, key: String, action: Selector) {
        let item = menu.items.first { $0.title == title }
        XCTAssertEqual(item?.keyEquivalent, key)
        XCTAssertEqual(item?.action, action)
    }
}
