import XCTest
@testable import Sendpoint

@MainActor
final class MicrophonePreviewOwnerTests: XCTestCase {
    private actor StartGate {
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private final class Recorder {
        var startedUIDs: [String?] = []
        var stopCount = 0
        var running = false
    }

    private func makeOwner(
        recorder: Recorder,
        gatedUIDs: Set<String> = [],
        gate: StartGate
    ) -> MicrophonePreviewOwner {
        MicrophonePreviewOwner(engine: .init(
            start: { order in
                let uid = order.entries.first?.uid
                recorder.startedUIDs.append(uid)
                recorder.running = true
                if let uid, gatedUIDs.contains(uid) {
                    await gate.wait()
                }
            },
            stop: {
                recorder.stopCount += 1
                recorder.running = false
            },
            isRunning: { recorder.running },
            level: { 0 }
        ))
    }

    private func order(_ uid: String) -> MicrophoneOrder {
        var order = MicrophoneOrder()
        order.absorb([AudioInputDevice(id: 1, uid: uid, name: uid, transport: .other)], systemDefault: nil)
        return order
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous test work")
    }

    func testStopCancelsPendingStartAndCleansUpStaleBringUp() async {
        let gate = StartGate()
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder, gatedUIDs: ["a"], gate: gate)

        owner.start(order("a"))
        await waitUntil { recorder.startedUIDs.count == 1 }
        XCTAssertEqual(recorder.stopCount, 1)
        owner.stop()
        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(recorder.stopCount, 2)

        await gate.release()
        await waitUntil { recorder.stopCount == 3 }
        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(recorder.startedUIDs, ["a"], "the stale bring-up never delivers a tap")
    }

    func testRestartSupersedesInFlightStart() async {
        let gate = StartGate()
        let recorder = Recorder()
        let owner = makeOwner(recorder: recorder, gatedUIDs: ["a"], gate: gate)

        owner.start(order("a"))
        await waitUntil { recorder.startedUIDs.count == 1 }
        owner.start(order("b"))

        await gate.release()
        await waitUntil { recorder.startedUIDs.count == 2 }
        XCTAssertEqual(recorder.startedUIDs, ["a", "b"])
        XCTAssertEqual(recorder.stopCount, 3)
        XCTAssertTrue(owner.isActive)

        owner.stop()
        XCTAssertFalse(owner.isActive)
    }
}
