import XCTest
@testable import Sendpoint

@MainActor
final class InputLevelMonitorTests: XCTestCase {
    @MainActor private final class SlowMicrophone {
        var started = false
        var stops = 0
        var startGate: CheckedContinuation<Void, Never>?

        var boundary: Microphone {
            Microphone(
                requestAccess: { true },
                prepare: { _ in },
                start: { _ in
                    self.started = true
                    await withCheckedContinuation { self.startGate = $0 }
                    return VoiceAudioQueue()
                },
                stop: { self.stops += 1 }
            )
        }

        func finishStart() {
            startGate?.resume()
            startGate = nil
        }
    }

    func testStopDuringSlowPreviewStartNeverReportsListening() async {
        let microphone = SlowMicrophone()
        let monitor = InputLevelMonitor(microphone: microphone.boundary, isAuthorized: { true })
        let starting = Task { await monitor.start(MicrophoneOrder()) }
        for _ in 0..<1_000 where !microphone.started { await Task.yield() }
        XCTAssertTrue(microphone.started)
        XCTAssertFalse(monitor.isRunning)

        monitor.stop()
        microphone.finishStart()
        await starting.value
        XCTAssertFalse(monitor.isRunning)
        XCTAssertGreaterThanOrEqual(microphone.stops, 2)
    }
}
