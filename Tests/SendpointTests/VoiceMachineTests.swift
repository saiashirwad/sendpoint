import XCTest
@testable import Sendpoint

final class VoiceMachineTests: XCTestCase {
    private let take = UUID()
    private let other = UUID()
    private let began = Date(timeIntervalSince1970: 1_000)

    private func recording() -> VoiceMachine {
        var machine = VoiceMachine()
        _ = machine.update(.start(take, modelReady: true))
        _ = machine.update(.micStarted(take, began))
        return machine
    }

    private func transcribing() -> VoiceMachine {
        var machine = recording()
        _ = machine.update(.stop(take, now: began.addingTimeInterval(2)))
        return machine
    }

    func testARecordingRunsFromStartToTranscript() {
        var machine = VoiceMachine()
        XCTAssertEqual(machine.update(.start(take, modelReady: true)), [.startMic(take)])
        XCTAssertEqual(machine.phase, .starting(take))
        XCTAssertEqual(machine.update(.micStarted(take, began)), [.emit(.started(take))])
        XCTAssertEqual(machine.update(.stop(take, now: began.addingTimeInterval(2))),
            [.stopMic, .finish(take), .prepare])
        XCTAssertEqual(machine.phase, .transcribing(take))
        XCTAssertEqual(machine.update(.transcribed(take, "hello")), [.emit(.transcript(take, "hello"))])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testAMissingModelFailsBeforeTheMicrophoneOpens() {
        var machine = VoiceMachine()
        XCTAssertEqual(machine.update(.start(take, modelReady: false)),
            [.emit(.failed(take, VoiceMachine.modelMissing))])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testDiscardWithNothingLiveDoesNothing() {
        var machine = VoiceMachine()
        XCTAssertEqual(machine.update(.discard), [], "closing a typed note must not touch the speech model")
        XCTAssertEqual(machine.phase, .idle)
    }

    func testDiscardDuringTranscriptionAbandonsTheModelSession() {
        var machine = transcribing()
        XCTAssertEqual(machine.update(.discard), [.abandon])
        XCTAssertEqual(machine.phase, .settling(next: nil))
        XCTAssertEqual(machine.update(.transcribed(take, "late")), [], "a cancelled transcript is dropped")
        XCTAssertEqual(machine.update(.settled), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testDiscardWhileRecordingReleasesTheMicrophoneAndSettles() {
        var machine = recording()
        XCTAssertEqual(machine.update(.discard), [.stopMic, .abandon, .prepare])
        XCTAssertEqual(machine.update(.discard), [], "a second discard starts no second abandon")
    }

    func testDiscardBeforeTheMicrophoneStartsNeedsNoSettling() {
        var machine = VoiceMachine()
        _ = machine.update(.start(take, modelReady: true))
        XCTAssertEqual(machine.update(.discard), [.stopMic])
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.update(.micStarted(take, began)), [], "a late microphone is ignored")
    }

    func testAStartWhileSettlingWaitsForTheModelToLetGo() {
        var machine = recording()
        _ = machine.update(.discard)
        XCTAssertEqual(machine.update(.start(other, modelReady: true)), [])
        XCTAssertEqual(machine.phase, .settling(next: other))
        XCTAssertEqual(machine.update(.settled), [.startMic(other)])
        XCTAssertEqual(machine.phase, .starting(other))
    }

    func testDiscardWhileSettlingForgetsTheQueuedStart() {
        var machine = recording()
        _ = machine.update(.discard)
        _ = machine.update(.start(other, modelReady: true))
        XCTAssertEqual(machine.update(.discard), [])
        XCTAssertEqual(machine.update(.settled), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testAStartOverALiveRecordingReplacesIt() {
        var machine = recording()
        XCTAssertEqual(machine.update(.start(other, modelReady: true)), [.stopMic, .abandon, .prepare])
        XCTAssertEqual(machine.phase, .settling(next: other))

        var starting = VoiceMachine()
        _ = starting.update(.start(take, modelReady: true))
        XCTAssertEqual(starting.update(.start(other, modelReady: true)), [.stopMic, .startMic(other)])
        XCTAssertEqual(starting.phase, .starting(other))
    }

    func testAClipTooShortToHoldSpeechYieldsAnEmptyTranscript() {
        var machine = recording()
        XCTAssertEqual(machine.update(.stop(take, now: began.addingTimeInterval(0.1))),
            [.stopMic, .abandon, .prepare, .emit(.transcript(take, ""))])
        XCTAssertEqual(machine.phase, .settling(next: nil))
    }

    func testFailuresReportOnceAndReleaseEverything() {
        var starting = VoiceMachine()
        _ = starting.update(.start(take, modelReady: true))
        XCTAssertEqual(starting.update(.micFailed(take, "mic busy")), [.stopMic, .emit(.failed(take, "mic busy"))])
        XCTAssertEqual(starting.phase, .idle)

        var machine = transcribing()
        XCTAssertEqual(machine.update(.transcriptionFailed(take, "model error")),
            [.abandon, .emit(.failed(take, "model error"))])
        XCTAssertEqual(machine.phase, .settling(next: nil))
    }

    func testResultsForAnotherTakeAndInvalidTransitionsAreIgnored() {
        var machine = recording()
        XCTAssertEqual(machine.update(.stop(other, now: began.addingTimeInterval(2))), [])
        XCTAssertEqual(machine.update(.micStarted(other, began)), [])
        XCTAssertEqual(machine.update(.transcribed(take, "early")), [])
        XCTAssertEqual(machine.update(.settled), [])
        XCTAssertEqual(machine.phase, .recording(take, since: began))

        var idle = VoiceMachine()
        XCTAssertEqual(idle.update(.stop(take, now: began)), [])
        XCTAssertEqual(idle.phase, .idle)
    }

    func testTeardownIsTerminalAndIdempotent() {
        var machine = recording()
        XCTAssertEqual(machine.update(.teardown), [.stopMic, .tearDown])
        XCTAssertEqual(machine.phase, .tornDown)
        for event: VoiceEvent in [.teardown, .warmUp, .start(other, modelReady: true), .discard, .settled] {
            XCTAssertEqual(machine.update(event), [])
        }
        XCTAssertEqual(machine.phase, .tornDown)
    }
}
