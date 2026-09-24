import XCTest
@testable import Sendpoint

@MainActor
final class MicrophonePreviewOwnerTests: XCTestCase {
    @MainActor private final class ScriptedMicrophone {
        var stops = 0
        var started: [String?] = []
        var finished = 0
        private var gates: [String: CheckedContinuation<Void, Never>] = [:]
        private let gated: Set<String>

        init(gated: Set<String>) {
            self.gated = gated
        }

        var boundary: Microphone {
            Microphone(
                requestAccess: { true },
                prepare: { _ in },
                start: { order in
                    let uid = order.entries.first?.uid
                    self.started.append(uid)
                    if let uid, self.gated.contains(uid) {
                        await withCheckedContinuation { self.gates[uid] = $0 }
                    }
                    self.finished += 1
                    return VoiceAudioQueue()
                },
                stop: { self.stops += 1 }
            )
        }

        func release(_ uid: String) {
            gates[uid]?.resume()
            gates[uid] = nil
        }
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test work")
    }

    private func owner(for microphone: ScriptedMicrophone) -> (MicrophonePreviewOwner, InputLevelMonitor) {
        let monitor = InputLevelMonitor(microphone: microphone.boundary, isAuthorized: { true })
        return (MicrophonePreviewOwner(monitor: monitor), monitor)
    }

    func testOneStartStopsOnceInsideTheMonitor() async {
        let microphone = ScriptedMicrophone(gated: [])
        let (owner, monitor) = owner(for: microphone)
        owner.start(order("a"))
        await waitUntil { monitor.isRunning }
        XCTAssertEqual(microphone.stops, 1, "the adapter must not add a stop before the monitor's stop")
        XCTAssertEqual(microphone.started, ["a"])
        XCTAssertTrue(owner.isActive)
    }

    func testStopDuringInFlightStartStopsOnceMore() async {
        let microphone = ScriptedMicrophone(gated: ["a"])
        let (owner, monitor) = owner(for: microphone)
        owner.start(order("a"))
        await waitUntil { microphone.started == ["a"] }
        XCTAssertEqual(microphone.stops, 1)
        XCTAssertFalse(monitor.isRunning)

        owner.stop()
        await waitUntil { microphone.stops == 2 }
        microphone.release("a")
        await waitUntil { microphone.finished == 1 }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(microphone.stops, 2, "the stale start must not stop again")
        XCTAssertFalse(owner.isActive)
        XCTAssertFalse(monitor.isRunning)
    }

    func testRestartSupersedesInFlightStart() async {
        let microphone = ScriptedMicrophone(gated: ["a"])
        let (owner, monitor) = owner(for: microphone)
        owner.start(order("a"))
        await waitUntil { microphone.started == ["a"] }
        owner.start(order("b"))
        await waitUntil { monitor.isRunning && microphone.started == ["a", "b"] }
        let stopsWhenRunning = microphone.stops
        XCTAssertTrue(owner.isActive)

        microphone.release("a")
        await waitUntil { microphone.finished == 2 }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(microphone.stops, stopsWhenRunning, "the loser must not stop after the winner is running")
        XCTAssertTrue(monitor.isRunning)
        XCTAssertTrue(owner.isActive)
        XCTAssertEqual(microphone.started, ["a", "b"])
    }
}
