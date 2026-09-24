import Foundation
import XCTest
import SendpointDomain

final class CaptureVoiceGestureTests: XCTestCase {
    private let context = NoteCaptureContext(stackID: UUID())
    private let selection = CapturedSelection(text: "")

    func testHoldReleaseClosesThePickerAndTranscribesToTheLastExplicitDestination() {
        let destination = UUID()
        var state = recording(mode: .hold)
        _ = state.update(.toggleDestinations(context))
        _ = state.update(.chooseDestination(context, destination))
        _ = state.update(.toggleDestinations(context))
        XCTAssertEqual(state.session?.destinationPicker, .open)

        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(context)])
        XCTAssertEqual(state.session?.phase, .transcribing)
        XCTAssertEqual(state.session?.destinationPicker, .closed)
        XCTAssertEqual(state.session?.destinationStackID, destination)

        let effects = state.update(.transcript(context, "Spoken draft"))
        guard case let .commit(request)? = effects.first else {
            return XCTFail("expected a commit, got \(effects)")
        }
        XCTAssertEqual(request.destinationStackID, destination)
        XCTAssertEqual(request.target.context.stackID, context.stackID)
        XCTAssertEqual(request.note.body, "Spoken draft")
    }

    func testTapStopShortcutStillWorksWithTheDestinationPickerOpen() {
        let destination = UUID()
        var state = recording(mode: .tap)
        XCTAssertEqual(state.update(.voiceReleased), [], "the first release keeps tap mode recording")
        _ = state.update(.toggleDestinations(context))
        _ = state.update(.chooseDestination(context, destination))
        _ = state.update(.toggleDestinations(context))

        XCTAssertEqual(state.update(.voicePressed), [.transcribe(context)])
        XCTAssertEqual(state.session?.phase, .transcribing)
        XCTAssertEqual(state.session?.destinationPicker, .closed)
        XCTAssertEqual(state.session?.destinationStackID, destination)
        XCTAssertEqual(state.update(.voiceReleased), [], "the stop press release is consumed")
    }

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

    func testAStoreChangeForTheSameStackLeavesAnOpenPickerAlone() {
        var state = recording(mode: .tap)
        _ = state.update(.toggleDestinations(context))

        XCTAssertEqual(state.update(.stackSelected(context.stackID)), [])
        XCTAssertEqual(state.session?.destinationPicker, .open)

        let other = UUID()
        XCTAssertEqual(state.update(.stackSelected(other)), [])
        XCTAssertEqual(state.session?.destinationStackID, other)
        XCTAssertEqual(state.session?.destinationPicker, .closed)
    }

    func testFinishingBeforeThePassageArrivesStartsOneDeadlineThenTranscribes() {
        var state = CaptureState()
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        _ = state.update(.recordingStarted(context))

        XCTAssertEqual(state.update(.voiceReleased), [.selectionDeadline(context)])
        XCTAssertEqual(state.update(.finishVoice), [], "a repeated finish starts no second deadline")
        XCTAssertEqual(state.update(.selection(context, selection)), [.transcribe(context)],
            "the deadline reports an empty passage, which releases the recording")
        XCTAssertEqual(state.session?.phase, .transcribing)
        XCTAssertEqual(state.update(.selection(context, selection)), [], "a late passage is dropped")
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

    func testEscapeDuringTranscriptionAbortsAndDropsTheLateTranscript() {
        var state = recording(mode: .hold)
        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(context)])
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
        XCTAssertEqual(state.update(.transcript(context, "too late")), [], "stale")
    }

    func testEscapeWithTheDestinationPickerOpenAbortsInOnePress() {
        var state = recording(mode: .hold)
        _ = state.update(.toggleDestinations(context))
        XCTAssertEqual(state.session?.destinationPicker, .open)
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
    }

    func testAnEmptyTranscriptClosesQuietlyAndSavesNothing() {
        var state = recording(mode: .hold)
        XCTAssertEqual(state.update(.voiceReleased), [.transcribe(context)])
        XCTAssertEqual(state.update(.transcript(context, " \n")), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
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

    // MARK: - Dictation

    private let target = DictationTarget(processIdentifier: 42, appName: "Safari")

    func testDictationHoldRecordsWithoutAPassageAndPastesTheTranscript() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.dictatePressed), [.beginDictation])
        XCTAssertEqual(state.update(.begin(.dictation, context, target)),
            [.show(.voice), .startRecording(context)], "no selection is read")
        XCTAssertEqual(state.session?.phase, .startingVoice)
        XCTAssertEqual(state.session?.dictationTarget, target)
        XCTAssertEqual(state.update(.recordingStarted(context)), [])
        XCTAssertEqual(state.session?.phase, .recording)
        XCTAssertEqual(state.update(.voicePartial(context, "hello")), [])
        XCTAssertEqual(state.session?.liveTranscript, "hello")

        XCTAssertEqual(state.update(.dictateReleased), [.transcribe(context)])
        XCTAssertEqual(state.update(.transcript(context, "hello there")),
            [.insert(context, "hello there", target)])
        XCTAssertEqual(state.session?.phase, .inserting)
        XCTAssertEqual(state.update(.voiceEscape), [], "a paste in flight cannot be cancelled")
        XCTAssertEqual(state.update(.inserted(NoteCaptureContext(stackID: UUID()), true)), [], "stale")
        XCTAssertEqual(state.update(.inserted(context, true)), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
        XCTAssertEqual(state.voice, VoiceGesture())
    }

    func testDictationTapFinishesOnTheSecondPress() {
        var state = CaptureState()
        _ = state.update(.voiceModeChanged(.tap))
        _ = state.update(.dictatePressed)
        _ = state.update(.begin(.dictation, context, target))
        _ = state.update(.recordingStarted(context))
        XCTAssertEqual(state.update(.dictateReleased), [], "tap mode keeps listening")
        XCTAssertEqual(state.update(.dictatePressed), [.transcribe(context)])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.voice, VoiceGesture(mode: .tap))
    }

    func testDictationWithNothingSaidClosesQuietlyAndNothingPastedShowsAMessage() {
        var state = dictating()
        _ = state.update(.dictateReleased)
        XCTAssertEqual(state.update(.transcript(context, "  ")), [.close])
        XCTAssertEqual(state.lifecycle, .idle)

        state = dictating()
        _ = state.update(.dictateReleased)
        _ = state.update(.transcript(context, "hello"))
        XCTAssertEqual(state.update(.inserted(context, false)), [.failureTimer(context)])
        XCTAssertEqual(state.session?.phase, .failed("Couldn’t paste."))
        XCTAssertEqual(state.update(.failureTimeout(context)), [.close])
    }

    func testDictationHasNoDestinationToChoose() {
        var state = dictating()
        XCTAssertEqual(state.session?.canChooseDestination, false)
        XCTAssertEqual(state.update(.toggleDestinations(context)), [])
        XCTAssertEqual(state.session?.destinationPicker, .closed)
    }

    func testTheOtherSpeechKeyBeepsOverAnOpenCaptureAndItsReleaseIsInert() {
        var state = recording(mode: .tap)
        _ = state.update(.voiceReleased)
        XCTAssertEqual(state.update(.dictatePressed), [.beep])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.session?.phase, .recording, "the note keeps recording")
        XCTAssertEqual(state.update(.voicePressed), [.transcribe(context)])

        state = dictating()
        XCTAssertEqual(state.update(.voicePressed), [], "one key at a time")
        XCTAssertEqual(state.update(.voiceReleased), [], "not the held key")
        XCTAssertEqual(state.session?.phase, .recording)
        XCTAssertEqual(state.update(.dictateReleased), [.transcribe(context)])
    }

    func testEscapeAndModeChangeCancelDictation() {
        var state = dictating()
        XCTAssertEqual(state.update(.voiceEscape), [.close])
        XCTAssertEqual(state.update(.dictateReleased), [], "still down after Escape")
        XCTAssertEqual(state.update(.dictatePressed), [.beginDictation])

        state = dictating()
        XCTAssertEqual(state.update(.voiceModeChanged(.tap)), [.close])
        XCTAssertEqual(state.lifecycle, .idle)
    }

    func testARefusedDictationWaitsForTheKeyToComeUp() {
        var state = CaptureState()
        XCTAssertEqual(state.update(.dictatePressed), [.beginDictation])
        XCTAssertEqual(state.update(.voiceRefused), [])
        XCTAssertEqual(state.update(.dictatePressed), [])
        XCTAssertEqual(state.update(.dictateReleased), [])
        XCTAssertEqual(state.update(.dictateToggled), [.beginDictation])
    }

    private func dictating() -> CaptureState {
        var state = CaptureState()
        _ = state.update(.dictatePressed)
        _ = state.update(.begin(.dictation, context, target))
        _ = state.update(.recordingStarted(context))
        return state
    }

    private func recording(mode: VoiceRecordingMode) -> CaptureState {
        var state = CaptureState()
        _ = state.update(.voiceModeChanged(mode))
        _ = state.update(.voicePressed)
        _ = state.update(.begin(.voice, context))
        _ = state.update(.recordingStarted(context))
        _ = state.update(.selection(context, selection))
        return state
    }
}
