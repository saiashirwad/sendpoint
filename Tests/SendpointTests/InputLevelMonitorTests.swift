import XCTest
@testable import Sendpoint

@MainActor
final class InputLevelMonitorTests: XCTestCase {
    @MainActor private final class Mic {
        enum Failure: Error { case start }
        var events: [String] = []
        var gate: CheckedContinuation<Void, Never>?
        var stopGate: CheckedContinuation<Void, Never>?
        var failStart = false
        var gateFailureStop = false
        var boundary: Microphone {
            Microphone(
                requestAccess: { XCTFail("Preview must not request permission"); return false },
                prepare: { _ in },
                start: { order, take in
                    XCTAssertNil(take)
                    let uid = order.entries.first?.uid ?? "default"
                    self.events.append("start \(uid)")
                    if self.failStart { throw Failure.start }
                    if uid == "a" { await withCheckedContinuation { self.gate = $0 } }
                    self.events.append("started \(uid)")
                },
                stop: {
                    self.events.append("stop")
                    if self.gateFailureStop, self.events.count == 3 {
                        await withCheckedContinuation { self.stopGate = $0 }
                    }
                },
                teardown: { self.events.append("teardown") }
            )
        }
        func release() { gate?.resume(); gate = nil }
        func releaseStop() { stopGate?.resume(); stopGate = nil }
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out")
    }

    func testStopWaitsForInFlightStartAndNeverReportsListening() async {
        let mic = Mic()
        let monitor = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor.start(order("a"))
        await waitUntil { mic.gate != nil }
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(mic.events, ["stop", "start a"])
        mic.release()
        await monitor.waitUntilSettled()
        XCTAssertEqual(mic.events, ["stop", "start a", "started a", "stop"])
        XCTAssertFalse(monitor.isRunning)
        monitor.teardown()
        await monitor.waitUntilSettled()
    }

    func testRestartWaitsForOldDeviceBeforeStartingTheNewOne() async {
        let mic = Mic()
        let monitor = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor.start(order("a"))
        await waitUntil { mic.gate != nil }
        monitor.start(order("b"))
        XCTAssertEqual(mic.events, ["stop", "start a"])
        mic.release()
        await monitor.waitUntilSettled()
        XCTAssertEqual(mic.events, ["stop", "start a", "started a", "stop", "start b", "started b"])
        XCTAssertTrue(monitor.isRunning)
        monitor.teardown()
        await monitor.waitUntilSettled()
    }

    func testUnauthorizedPreviewAndTerminalTeardownNeverStart() async {
        let mic = Mic()
        let monitor = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { false })
        monitor.start(order("b"))
        await monitor.waitUntilSettled()
        XCTAssertFalse(monitor.isRunning)
        monitor.teardown()
        monitor.teardown()
        monitor.start(order("b"))
        await monitor.waitUntilSettled()
        XCTAssertEqual(mic.events, ["stop", "stop", "teardown"])
    }

    func testOwnerReleaseDuringStartCleansUpAfterTheLateDeviceReturns() async {
        let mic = Mic()
        var monitor: InputLevelMonitor? = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor?.start(order("a"))
        await waitUntil { mic.gate != nil }
        weak let released = monitor
        monitor = nil
        XCTAssertNil(released, "The external start must not retain the preview owner")
        XCTAssertEqual(mic.events, ["stop", "start a"])
        mic.release()
        await waitUntil { mic.events.last == "teardown" }
        XCTAssertEqual(mic.events, ["stop", "start a", "started a", "stop", "teardown"])
    }

    func testOwnerReleaseWhileRunningStopsAndReleasesTheDevice() async {
        let mic = Mic()
        var monitor: InputLevelMonitor? = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor?.start(order("b"))
        await waitUntil { monitor?.isRunning == true }
        weak let released = monitor
        monitor = nil
        XCTAssertNil(released)
        await waitUntil { mic.events.last == "teardown" }
        XCTAssertEqual(mic.events, ["stop", "start b", "started b", "stop", "teardown"])
    }

    func testPageReplacementStopThenStartUsesTheSameOrderedOwner() async {
        let mic = Mic()
        let monitor = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor.start(order("a"))
        await waitUntil { mic.gate != nil }
        monitor.stop()
        monitor.start(order("b"))
        XCTAssertEqual(mic.events, ["stop", "start a"])
        mic.release()
        await monitor.waitUntilSettled()
        XCTAssertEqual(mic.events, ["stop", "start a", "started a", "stop", "stop", "start b", "started b"])
        XCTAssertTrue(monitor.isRunning)
        monitor.teardown()
        await monitor.waitUntilSettled()
    }

    func testWaitUntilSettledIncludesFailureShutdown() async {
        let mic = Mic()
        mic.failStart = true
        mic.gateFailureStop = true
        let monitor = InputLevelMonitor(microphone: mic.boundary, isAuthorized: { true })
        monitor.start(order("b"))
        var settled = false
        let waiting = Task { await monitor.waitUntilSettled(); settled = true }
        await waitUntil { mic.stopGate != nil }
        XCTAssertFalse(settled)
        mic.releaseStop()
        await waiting.value
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(mic.events, ["stop", "start b", "stop"])
        monitor.teardown()
        await monitor.waitUntilSettled()
    }
}
