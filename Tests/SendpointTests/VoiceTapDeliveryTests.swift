import XCTest
@testable import Sendpoint

/// The tap-level stale-delivery guard, deterministically and without
/// hardware: a level delivered for an older recording generation must not
/// move the meter, while the live generation still applies. `discardRecording`
/// advances the generation on an idle service (no engine, model, or tap).
@MainActor
final class VoiceTapDeliveryTests: XCTestCase {
    func testStaleTapLevelDoesNotMoveMeter() {
        let service = VoiceNoteService()
        let live = service.recordingEpoch

        service.applyTapLevel(1.0, epoch: live)
        XCTAssertEqual(service.levelMeter.current, 1.0, "the live generation applies")

        service.levelMeter.reset()
        service.discardRecording()
        XCTAssertNotEqual(service.recordingEpoch, live, "discard advances the generation without hardware")

        service.applyTapLevel(1.0, epoch: live)
        XCTAssertEqual(
            service.levelMeter.current, 0.0,
            "a late flush from a discarded recording must not raise the meter after reset"
        )
    }
}
