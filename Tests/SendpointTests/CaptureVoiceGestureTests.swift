import Foundation
import XCTest
@testable import Sendpoint

/// The voice key as the reducer sees it: a repeat, an early failure, or
/// Escape must never start a second recording.
final class CaptureVoiceGestureTests: XCTestCase {
    private let context = NoteCaptureContext(stackID: UUID())
    private let selection = CapturedSelection(text: "")

    func testHoldFinishesOnReleaseAndIgnoresRepeatsWhileDown() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.voiceReleased), [], "a release with nothing held is inert")
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
        XCTAssertEqual(state.update(.begin(.voice, context)),
            [.show(.voice), .startRecording(context), .readSelection(context, .voice)])
        XCTAssertEqual(state.update(.voicePressed), [], "key repeat")
        XCTAssertEqual(state.update(.recordingStarted(context)), [])
        XCTAssertEqual(state.update(.selection(context, selection)), [])
        XCTAssertEqual(state.session?.phase, .recording)

        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(context)])
        XCTAssertEqual(state.session?.phase, .transcribing)
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.voice, VoiceGesture())
    }

    func testTapWaitsForASecondPressAndConsumesItsRelease() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.voiceModeChanged(.tap)), [])
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        _ = state.update(.recordingStarted(context))
        _ = state.update(.selection(context, selection))
        XCTAssertEqual(state.update(.voiceReleased), [], "tap mode keeps recording after the release")
        XCTAssertEqual(state.session?.phase, .recording)

        XCTAssertEqual(state.update(.voicePressed), [.transcribe(context)])
        XCTAssertEqual(state.update(.voicePressed), [], "the finishing press repeats harmlessly")
        XCTAssertEqual(state.voice.releasePending, true)
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.voice, VoiceGesture(mode: .tap))
    }

    func testReleaseBeforeRecordingStartsEndsTheCaptureWithoutTranscribing() {
        var state = CaptureState()
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        XCTAssertEqual(state.update(.voiceReleased), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
        XCTAssertEqual(state.update(.recordingStarted(context)), [], "a late start has no capture to join")
    }

    func testEscapeWhileHeldCancelsAndConsumesTheRelease() {
        for mode in VoiceRecordingMode.allCases {
            var state = CaptureState()
            _ = state.update(.voiceModeChanged(mode))
            _ = state.update(.voicePressed)
            _ = state.update(.begin(.voice, context))
            _ = state.update(.recordingStarted(context))
            XCTAssertEqual(state.update(.voiceEscape), [.close])
            XCTAssertEqual(state.lifecycle, .idle)
            XCTAssertEqual(state.update(.voicePressed), [], "still down after Escape")
            XCTAssertEqual(state.update(.voiceEscape), [], "nothing left to cancel")
            XCTAssertEqual(state.update(.voiceReleased), [])
            XCTAssertEqual(state.update(.voicePressed), [.beginVoice], "\(mode): a fresh press starts over")
        }
    }

    func testEscapeCancelsATapRecordingOnce() {
        var state = CaptureState()
        _ = state.update(.voiceModeChanged(.tap))
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.update(.voiceEscape), [])
        XCTAssertEqual(state.voice, VoiceGesture(mode: .tap))
    }

    func testRefusedStartCannotRetryUntilTheKeyComesUp() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
        XCTAssertEqual(state.update(.voiceRefused), [])
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
    }

    func testACaptureThatEndsWhileHeldConsumesTheRelease() {
        var state = CaptureState()
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        XCTAssertEqual(state.update(.failed(context, "no microphone")), [.failureTimer(context)])
        XCTAssertEqual(state.update(.failureTimeout(context)), [.close])
        XCTAssertEqual(state.update(.voicePressed), [], "the failed press is still down")
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
    }

    func testModeChangeCancelsTheCaptureAndForgetsTheOldPress() {
        for mode in VoiceRecordingMode.allCases {
            var state = CaptureState()
            _ = state.update(.voiceModeChanged(mode))
            _ = state.update(.voicePressed)
            _ = state.update(.begin(.voice, context))
            if mode == .tap { _ = state.update(.voiceReleased) }
            XCTAssertEqual(state.update(.voiceModeChanged(.hold)), [.close])
            XCTAssertEqual(state.update(.voiceReleased), [])
            XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
        }
    }

    func testMenuToggleStartsAndFinishesInBothModes() {
        for mode in VoiceRecordingMode.allCases {
            var state = CaptureState()
            _ = state.update(.voiceModeChanged(mode))
            XCTAssertEqual(state.update(.voiceToggled), [.beginVoice])
            _ = state.update(.begin(.voice, context))
            _ = state.update(.recordingStarted(context))
            _ = state.update(.selection(context, selection))
            XCTAssertEqual(state.update(.voiceReleased), [], "no key was ever down")
            XCTAssertEqual(state.update(.voiceToggled), [.transcribe(context)])
            XCTAssertEqual(state.update(.voiceToggled), [.beep], "\(mode): nothing left to finish")
        }
    }

    func testPressWhileATypedNoteIsOpenFocusesItAndConsumesTheRelease() {
        var state = CaptureState()
        _ = state.update(.begin(.text, context))
        _ = state.update(.selectionPending(context))
        XCTAssertEqual(state.update(.voicePressed), [.focusEditor])
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.voice, VoiceGesture())
        XCTAssertEqual(state.session?.phase, .editing(""))
    }
}
