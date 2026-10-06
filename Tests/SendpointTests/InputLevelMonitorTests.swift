import XCTest
@testable import Sendpoint

@MainActor
final class InputLevelMonitorTests: XCTestCase {
    @MainActor private final class Mic {
        var events: [String] = []
        var gate: CheckedContinuation<Void, Never>?
        var boundary: Microphone {
            Microphone(
                requestAccess: { XCTFail("Preview must not request permission"); return false },
                prepare: { _ in },
                start: { order in
                    let uid = order.entries.first?.uid ?? "default"
                    self.events.append("start \(uid)")
                    if uid == "a" { await withCheckedContinuation { self.gate = $0 } }
                    self.events.append("started \(uid)")
                    return VoiceAudioQueue()
                },
                stop: { self.events.append("stop") },
                teardown: { self.events.append("teardown") }
            )
        }
        func release() { gate?.resume(); gate = nil }
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
}
