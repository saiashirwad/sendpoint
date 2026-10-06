import Foundation
import XCTest
import SendpointDomain

final class CaptureVoiceGestureTests: XCTestCase {
    private let identity = CaptureIdentity(sourceStack: .one)
    private let selection = CapturedSelection(text: "Selected quote")
    private let target = DictationTarget(processIdentifier: 42, appName: "Safari")

    func testHoldReleaseFreezesDestinationAndCommitsWithOriginalIdentityAndSelection() {
        var state = recording(mode: .hold)
        _ = state.update(.toggleDestinations(identity))
        XCTAssertEqual(state.update(.chooseDestination(identity, .two)), [.switchStack(.two)])
        _ = state.update(.toggleDestinations(identity))
        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(identity)])
        XCTAssertEqual(state.destination, .frozen(.two))
        _ = state.update(.stackSelected(.five))
        _ = state.update(.chooseDestination(identity, .four))
        let effects = state.update(.transcript(identity, "Spoken draft"))
        guard case let .commit(request)? = effects.first else { return XCTFail("Expected commit") }
        XCTAssertEqual(request.destinationStackID, .two)
        XCTAssertEqual(request.identity, identity)
        XCTAssertEqual(request.selection, selection)
        XCTAssertEqual(request.note.body, "Spoken draft")
        XCTAssertEqual(request.input, .voice)
    }

    func testTapStopWorksWithPickerOpenAndConsumesTheSecondPressRelease() {
        var state = recording(mode: .tap)
        XCTAssertEqual(state.update(.voiceReleased), [])
        _ = state.update(.toggleDestinations(identity))
        XCTAssertEqual(state.update(.voicePressed), [.transcribe(identity)])
        XCTAssertEqual(state.destination, .frozen(.one))
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.speechLatch, .up)
    }

    func testHeldKeyRepeatsAndUnmatchedReleasesAreInert() {
        var state = recording(mode: .hold)
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.speech?.stage, .listening)
        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(identity)])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.speechLatch, .up)
    }

    func testBothSelectionAndRecordingArrivalOrdersJoinWithoutChangingDestination() {
        for selectionFirst in [true, false] {
            var state = CaptureState()
            _ = state.update(.begin(.voice(identity)))
            _ = state.update(.stackSelected(.three))
            if selectionFirst {
                _ = state.update(.selection(identity, selection))
                XCTAssertEqual(state.speech?.stage, .starting)
                _ = state.update(.recordingStarted(identity))
            } else {
                _ = state.update(.recordingStarted(identity))
                XCTAssertNil(state.captured)
                _ = state.update(.selection(identity, selection))
            }
            XCTAssertEqual(state.speech?.stage, .listening)
            XCTAssertEqual(state.captured, selection)
            XCTAssertEqual(state.destination, .choosing(.closed(.three)))
            XCTAssertEqual(state.update(.finishVoice), [.transcribe(identity)])
        }
    }

    func testFinishBeforeSelectionCreatesOneFrozenJoinAndKeepsPreviewUntilSelectionArrives() {
        var state = CaptureState()
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice(identity)))
        _ = state.update(.recordingStarted(identity))
        _ = state.update(.voicePartial(identity, "early preview"))
        _ = state.update(.stackSelected(.two))
        XCTAssertEqual(state.update(.voiceReleased), [.selectionDeadline(identity)])
        XCTAssertEqual(state.work, .joiningVoice(.two, "early preview"))
        XCTAssertEqual(state.update(.finishVoice), [])
        _ = state.update(.stackSelected(.five))
        _ = state.update(.voicePartial(identity, "updated preview"))
        XCTAssertEqual(state.destination, .frozen(.two))
        XCTAssertEqual(state.update(.selection(identity, selection)), [.transcribe(identity)])
        XCTAssertEqual(state.work, .transcribing(.note(selection, .two), "updated preview"))
        XCTAssertEqual(state.update(.selection(identity, CapturedSelection(text: "late"))), [])
    }

    func testReleaseBeforeRecordingStartsClosesInEitherSelectionOrder() {
        for selectionFirst in [true, false] {
            var state = CaptureState()
            _ = state.update(.voicePressed)
            _ = state.update(.begin(.voice(identity)))
            if selectionFirst { _ = state.update(.selection(identity, selection)) }
            XCTAssertEqual(state.update(.voiceReleased), [.close])
            XCTAssertEqual(state.lifecycle, .idle)
            XCTAssertEqual(state.update(.recordingStarted(identity)), [])
            XCTAssertEqual(state.update(.selection(identity, selection)), [])
        }
    }

    func testStackChangesFollowWhileChoosingAndSameSlotDoesNotCloseThePicker() {
        var state = recording(mode: .tap)
        _ = state.update(.toggleDestinations(identity))
        _ = state.update(.stackSelected(.one))
        XCTAssertEqual(state.destination, .choosing(.picking(.one)))
        _ = state.update(.stackSelected(.two))
        XCTAssertEqual(state.destination, .choosing(.closed(.two)))
        XCTAssertEqual(state.captured, selection)
    }

    func testEscapeWhileHeldCancelsOnceAndConsumesReleaseInBothModes() {
        for mode in VoiceRecordingMode.allCases {
            var state = recording(mode: mode)
            _ = state.update(.toggleDestinations(identity))
            XCTAssertEqual(state.update(.voiceEscape), [.close])
            XCTAssertEqual(state.update(.voicePressed), [])
            XCTAssertEqual(state.update(.voiceEscape), [])
            XCTAssertEqual(state.update(.voiceReleased), [])
            XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
        }
    }

    func testEscapeDuringTranscriptionDropsLateResults() {
        var state = recording(mode: .hold)
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.update(.transcript(identity, "too late")), [])
        XCTAssertEqual(state.lifecycle, .idle)
    }

    func testEscapeAfterTapReleaseDoesNotBlockNextPress() {
        var state = recording(mode: .tap)
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
    }

    func testRefusedStartsWaitForTheCorrespondingRelease() {
        for key in [SpeechKey.note, .dictate] {
            var state = CaptureState()
            let press: CaptureEvent = key == .note ? .voicePressed : .dictatePressed
            let release: CaptureEvent = key == .note ? .voiceReleased : .dictateReleased
            let begin: CaptureEffect = key == .note ? .beginVoice : .beginDictation
            XCTAssertEqual(state.update(press), [begin])
            _ = state.update(.voiceRefused)
            XCTAssertEqual(state.update(press), [])
            _ = state.update(key == .note ? .dictateReleased : .voiceReleased)
            XCTAssertEqual(state.update(press), [])
            _ = state.update(release)
            XCTAssertEqual(state.update(press), [begin])
        }
    }

    func testFailureRetainsOriginAndSelectionButClearsPreviewThenConsumesHeldRelease() {
        var state = recording(mode: .hold)
        _ = state.update(.voicePartial(identity, "preview"))
        XCTAssertEqual(state.update(.failed(identity, "no microphone")), [.failureTimer(identity)])
        XCTAssertEqual(state.speech?.origin, .note(.resolved(selection), .one))
        XCTAssertEqual(state.captured, selection)
        XCTAssertNil(state.speech?.preview)
        XCTAssertEqual(state.update(.failureTimeout(identity)), [.close])
        XCTAssertEqual(state.update(.voicePressed), [])
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
    }

    func testModeChangeCancelsAndForgetsTheOldPress() {
        for mode in VoiceRecordingMode.allCases {
            var state = recording(mode: mode)
            if mode == .tap { _ = state.update(.voiceReleased) }
            XCTAssertEqual(state.update(.voiceModeChanged(.hold)), [.close])
            XCTAssertEqual(state.update(.voiceReleased), [])
            XCTAssertEqual(state.update(.voicePressed), [.beginVoice])
        }
    }

    func testMenuToggleStartsAndFinishesWithoutAKeyInBothModes() {
        for mode in VoiceRecordingMode.allCases {
            var state = CaptureState()
            _ = state.update(.voiceModeChanged(mode))
            XCTAssertEqual(state.update(.voiceToggled), [.beginVoice])
            _ = state.update(.begin(.voice(identity)))
            _ = state.update(.selection(identity, selection))
            _ = state.update(.recordingStarted(identity))
            XCTAssertEqual(state.update(.voiceReleased), [])
            XCTAssertEqual(state.update(.voiceToggled), [.transcribe(identity)])
            XCTAssertEqual(state.update(.voiceToggled), [.beep])
        }
    }

    func testSpeechPressOverTypedEditorFocusesItAndConsumesRelease() {
        var state = CaptureState()
        _ = state.update(.begin(.typed(identity)))
        _ = state.update(.selectionPending(identity))
        XCTAssertEqual(state.update(.voicePressed), [.focusEditor])
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.editor, .editing(""))
        XCTAssertEqual(state.speechLatch, .up)
    }

    func testDictationRequiresPIDReadsNoSelectionAndCannotChooseAStack() {
        var state = CaptureState()
        _ = state.update(.dictatePressed)
        XCTAssertEqual(state.update(.begin(.dictation(identity, target))), [.show(.voice), .startRecording(identity)])
        XCTAssertEqual(state.speech?.origin, .dictation(target))
        XCTAssertNil(state.destination)
        XCTAssertEqual(state.update(.selection(identity, selection)), [])
        XCTAssertEqual(state.update(.toggleDestinations(identity)), [])
        XCTAssertEqual(state.update(.stackSelected(.five)), [])
        _ = state.update(.recordingStarted(identity))
        _ = state.update(.voicePartial(identity, "hello"))
        XCTAssertEqual(state.speech?.preview, "hello")
        XCTAssertEqual(state.update(.dictateReleased), [.transcribe(identity)])
        XCTAssertEqual(state.update(.transcript(identity, "hello there")), [.insert(identity, "hello there", target)])
        XCTAssertEqual(state.work, .inserting(target, "hello there"))
        XCTAssertEqual(state.update(.voiceEscape), [])
        XCTAssertEqual(state.update(.inserted(CaptureIdentity(sourceStack: .two), true)), [])
        XCTAssertEqual(state.update(.inserted(identity, true)), [.close])
    }

    func testDictationTapFinishesOnSecondPressAndConsumesRelease() {
        var state = dictating(mode: .tap)
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.update(.dictatePressed), [.transcribe(identity)])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.speechLatch, .up)
    }

    func testEmptyTranscriptsCloseWithoutSavingOrPasting() {
        for dictate in [false, true] {
            var state = dictate ? dictating() : recording(mode: .hold)
            _ = state.update(dictate ? .dictateReleased : .voiceReleased)
            XCTAssertEqual(state.update(.transcript(identity, " \n")), [.close])
            XCTAssertEqual(state.lifecycle, .idle)
        }
    }

    func testFailedPasteKeepsDictationOriginThenTimesOut() {
        var state = dictating()
        _ = state.update(.dictateReleased)
        _ = state.update(.transcript(identity, "hello"))
        XCTAssertEqual(state.update(.inserted(identity, false)), [.failureTimer(identity)])
        XCTAssertEqual(state.speech?.stage, .failed("Couldn’t paste."))
        XCTAssertEqual(state.speech?.origin, .dictation(target))
        XCTAssertEqual(state.update(.failureTimeout(identity)), [.close])
    }

    func testOtherSpeechKeyBeepsOverTapCaptureButDoesNotFinishIt() {
        var state = recording(mode: .tap)
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.dictatePressed), [.beep])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.speech?.stage, .listening)
        XCTAssertEqual(state.update(.voicePressed), [.transcribe(identity)])

        state = dictating()
        XCTAssertEqual(state.update(.voicePressed), [])
        XCTAssertEqual(state.update(.voiceReleased), [])
        XCTAssertEqual(state.update(.dictateReleased), [.transcribe(identity)])
    }

    func testEscapeAndModeChangeCancelDictation() {
        var state = dictating()
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        _ = state.update(.dictateReleased)
        XCTAssertEqual(state.update(.dictatePressed), [.beginDictation])
        state = dictating()
        XCTAssertEqual(state.update(.voiceModeChanged(.tap)), [.close])
    }

    private func dictating(mode: VoiceRecordingMode = .hold) -> CaptureState {
        var state = CaptureState()
        _ = state.update(.voiceModeChanged(mode))
        _ = state.update(.dictatePressed)
        _ = state.update(.begin(.dictation(identity, target)))
        _ = state.update(.recordingStarted(identity))
        return state
    }

    private func recording(mode: VoiceRecordingMode) -> CaptureState {
        var state = CaptureState()
        _ = state.update(.voiceModeChanged(mode))
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice(identity)))
        _ = state.update(.recordingStarted(identity))
        _ = state.update(.selection(identity, selection))
        return state
    }
}
