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
}
