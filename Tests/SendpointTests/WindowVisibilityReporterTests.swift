import AppKit
import XCTest
@testable import Sendpoint

@MainActor
final class WindowVisibilityReporterTests: XCTestCase {
    private final class Window: NSWindow {
        var shown = false
        var exposed = false
        override var isVisible: Bool { shown }
        override var occlusionState: NSWindow.OcclusionState { exposed ? [.visible] : [] }

        func change(shown: Bool, exposed: Bool) {
            self.shown = shown
            self.exposed = exposed
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    func testHiddenAndOccludedWindowsStopVisibleWork() async {
        let window = Window()
        let reporter = WindowVisibilityReporter.ReporterView()
        var values: [Bool] = []
        reporter.onChange = { values.append($0) }
        window.contentView = reporter
        await settle()
        XCTAssertEqual(values.last, false)

        window.change(shown: true, exposed: true)
        await settle()
        XCTAssertEqual(values.last, true)

        window.change(shown: true, exposed: false)
        await settle()
        XCTAssertEqual(values.last, false)

        window.change(shown: true, exposed: true)
        await settle()
        XCTAssertEqual(values.last, true)

        window.change(shown: false, exposed: true)
        await settle()
        XCTAssertEqual(values.last, false)
        reporter.teardown()
    }

    func testNewerVisibilitySupersedesQueuedDeliveryAndCloseStopsWork() async {
        let window = Window()
        let reporter = WindowVisibilityReporter.ReporterView()
        var values: [Bool] = []
        reporter.onChange = { values.append($0) }
        window.contentView = reporter
        window.change(shown: true, exposed: true)
        window.change(shown: false, exposed: false)
        await settle()
        XCTAssertEqual(values, [false], "A queued visible result must not restart hidden work")

        window.change(shown: true, exposed: true)
        await settle()
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        await settle()
        XCTAssertEqual(values, [false, true, false])
        reporter.teardown()
    }

    func testReattachmentIgnoresOldWindowAndTeardownCancelsPendingReport() async {
        let oldWindow = Window()
        let newWindow = Window()
        let reporter = WindowVisibilityReporter.ReporterView()
        var values: [Bool] = []
        reporter.onChange = { values.append($0) }
        oldWindow.contentView = reporter
        oldWindow.change(shown: true, exposed: true)
        oldWindow.contentView = nil
        newWindow.contentView = reporter
        await settle()
        XCTAssertEqual(values, [false])

        oldWindow.change(shown: true, exposed: true)
        await settle()
        XCTAssertEqual(values, [false])

        newWindow.change(shown: true, exposed: true)
        reporter.teardown()
        reporter.teardown()
        await settle()
        XCTAssertEqual(values, [false])
        newWindow.change(shown: true, exposed: true)
        await settle()
        XCTAssertEqual(values, [false])
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }
}
