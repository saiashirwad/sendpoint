import AppKit
import XCTest
@testable import Sendpoint

@MainActor
final class SelectionCaptureClipboardTests: XCTestCase {
    @MainActor
    private final class ModifierGate {
        private var waiter: CheckedContinuation<Void, Never>?
        private(set) var isWaiting = false

        func wait() async {
            isWaiting = true
            await withCheckedContinuation { waiter = $0 }
        }

        func release() {
            waiter?.resume()
            waiter = nil
        }
    }

    func testAClipboardChangeWhileModifiersAreHeldSurvivesTheSyntheticCopy() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        write("before recording", to: pasteboard)
        let gate = ModifierGate()

        let capture = Task { @MainActor in
            try await SelectionCapture.copyViaKeystroke(
                pasteboard: pasteboard, processIdentifier: 0, fallback: .brief, editorMayOpen: {},
                waitForModifierRelease: { _ in await gate.wait() },
                postCopy: { _ in self.write("selection", to: pasteboard) }
            )
        }
        for _ in 0..<2000 where !gate.isWaiting { await Task.yield() }
        XCTAssertTrue(gate.isWaiting)

        write("copied during recording", to: pasteboard)
        gate.release()
        let copied = try await capture.value

        XCTAssertEqual(copied, "selection")
        XCTAssertEqual(pasteboard.string(forType: .string), "copied during recording")
    }

    private func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
