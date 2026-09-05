import XCTest
@testable import Sendpoint

final class VoiceTriggerMachineTests: XCTestCase {
    func testDefaultHoldFinishesOnReleaseEvenForAnImmediateTap() {
        var machine = VoiceTriggerMachine()
        XCTAssertEqual(machine.mode, .hold)
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.handle(.pressed), [.beginCapture])
        XCTAssertEqual(machine.handle(.pressed), [])
        XCTAssertEqual(machine.handle(.released), [.finishCapture])
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testTapWaitsForSecondPressAndIgnoresRepeatsThroughCompletion() {
        var machine = VoiceTriggerMachine()
        XCTAssertEqual(machine.handle(.configurationChanged(.tap)), [])
        XCTAssertEqual(machine.handle(.pressed), [.beginCapture])
        XCTAssertEqual(machine.handle(.pressed), [])
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.state, .recording)
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.handle(.pressed), [.finishCapture])
        XCTAssertEqual(machine.handle(.captureEnded), [])
        XCTAssertEqual(machine.handle(.captureEnded), [])
        XCTAssertEqual(machine.handle(.pressed), [])
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.handle(.pressed), [.beginCapture])
    }

    func testEscapeWhileHeldConsumesReleaseEvenIfTeardownFinishesSynchronously() {
        for mode in VoiceRecordingMode.allCases {
            var machine = VoiceTriggerMachine()
            _ = machine.handle(.configurationChanged(mode))
            _ = machine.handle(.pressed)
            XCTAssertEqual(machine.handle(.escape), [.cancelCapture])
            XCTAssertEqual(machine.handle(.captureEnded), [])
            XCTAssertEqual(machine.handle(.pressed), [])
            XCTAssertEqual(machine.handle(.escape), [])
            XCTAssertEqual(machine.handle(.released), [])
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testEscapeCancelsTapRecordingOnce() {
        var machine = VoiceTriggerMachine()
        _ = machine.handle(.configurationChanged(.tap))
        _ = machine.handle(.pressed)
        _ = machine.handle(.released)
        XCTAssertEqual(machine.handle(.escape), [.cancelCapture])
        XCTAssertEqual(machine.handle(.captureEnded), [])
        XCTAssertEqual(machine.handle(.escape), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testStartupFailureCannotRestartUntilRelease() {
        var machine = VoiceTriggerMachine()
        _ = machine.handle(.pressed)
        XCTAssertEqual(machine.handle(.captureEnded), [])
        XCTAssertEqual(machine.handle(.pressed), [])
        XCTAssertEqual(machine.handle(.released), [])
        XCTAssertEqual(machine.handle(.pressed), [.beginCapture])
    }

    func testConfigurationChangeCancelsHeldOrTapRecordingAndRejectsOldRelease() {
        for mode in VoiceRecordingMode.allCases {
            var machine = VoiceTriggerMachine()
            _ = machine.handle(.configurationChanged(mode))
            _ = machine.handle(.pressed)
            if mode == .tap { _ = machine.handle(.released) }
            XCTAssertEqual(machine.handle(.configurationChanged(.hold)), [.cancelCapture])
            XCTAssertEqual(machine.handle(.captureEnded), [])
            XCTAssertEqual(machine.handle(.released), [])
            XCTAssertEqual(machine.handle(.configurationChanged(.tap)), [])
            XCTAssertEqual(machine.handle(.pressed), [.beginCapture])
        }
    }

    func testMenuStartStopWorksInBothModesWithoutSyntheticKeyEvents() {
        for mode in VoiceRecordingMode.allCases {
            var machine = VoiceTriggerMachine()
            _ = machine.handle(.configurationChanged(mode))
            XCTAssertEqual(machine.handle(.menuToggle), [.beginCapture])
            XCTAssertEqual(machine.handle(.released), [])
            XCTAssertEqual(machine.handle(.menuToggle), [.finishCapture])
            XCTAssertEqual(machine.state, .idle)
            XCTAssertEqual(machine.handle(.menuToggle), [.beginCapture])
            XCTAssertEqual(machine.handle(.pressed), [.finishCapture])
            XCTAssertEqual(machine.handle(.captureEnded), [])
            XCTAssertEqual(machine.handle(.pressed), [])
            XCTAssertEqual(machine.handle(.released), [])
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testMenuStartupFailureAndConfigurationChangeResetRecording() {
        var machine = VoiceTriggerMachine()
        _ = machine.handle(.menuToggle)
        XCTAssertEqual(machine.handle(.captureEnded), [])
        XCTAssertEqual(machine.state, .idle)
        _ = machine.handle(.menuToggle)
        XCTAssertEqual(machine.handle(.configurationChanged(.tap)), [.cancelCapture])
        XCTAssertEqual(machine.state, .idle)
    }
}
