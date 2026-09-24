import Foundation
import XCTest
import SendpointDomain

final class PermissionMachineTests: XCTestCase {
    private func live(
        accessibility: AccessibilityPermissionState = .granted,
        microphone: MicrophonePermissionState = .granted,
        model: LocalVoiceModelState = .ready
    ) -> PermissionState {
        PermissionState(accessibility: accessibility, microphone: microphone, localVoiceModel: model)
    }

    func testGrantedMicrophoneRequestAndReadyDownloadAreInvalid() throws {
        var state = live()
        XCTAssertEqual(state.update(.requestMicrophone), [])
        XCTAssertEqual(state.update(.downloadVoiceModel), [])
        XCTAssertNil(state.microphoneRequest)
        XCTAssertNil(state.modelDownload)
        XCTAssertEqual(state.microphone, .granted)
        XCTAssertEqual(state.localVoiceModel, .ready)

        state.localVoiceModel = .notDownloaded
        let effects = state.update(.downloadVoiceModel)
        let id = try XCTUnwrap(state.modelDownload)
        XCTAssertEqual(effects, [.downloadModel(id)])
        XCTAssertEqual(state.update(.downloadProgress(UUID(), 0.4)), [])
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
    }

    func testStaleMicrophoneAndDownloadResultsDoNothing() throws {
        var state = live(microphone: .notDetermined, model: .notDownloaded)
        _ = state.update(.requestMicrophone)
        let microphoneID = try XCTUnwrap(state.microphoneRequest)
        _ = state.update(.downloadVoiceModel)
        let downloadID = try XCTUnwrap(state.modelDownload)

        XCTAssertEqual(state.update(.microphoneResolved(UUID(), granted: true)), [])
        XCTAssertEqual(state.microphone, .notDetermined)
        XCTAssertEqual(state.microphoneRequest, microphoneID)
        XCTAssertEqual(state.update(.microphoneStatus(.denied)), [])
        XCTAssertEqual(state.microphone, .notDetermined)

        XCTAssertEqual(state.update(.downloadProgress(UUID(), 0.5)), [])
        XCTAssertEqual(state.update(.downloadFailed(UUID(), .offline)), [])
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        XCTAssertEqual(state.modelDownload, downloadID)

        state.localVoiceModel = .ready
        XCTAssertEqual(state.update(.downloadFailed(downloadID, .other)), [.stopDownloadProgress])
        XCTAssertEqual(state.localVoiceModel, .ready)
        XCTAssertNil(state.modelDownload)
        XCTAssertEqual(state.update(.downloadProgress(downloadID, 0.2)), [])
        XCTAssertEqual(state.localVoiceModel, .ready)

        XCTAssertEqual(state.update(.microphoneResolved(microphoneID, granted: true)), [])
        XCTAssertEqual(state.microphone, .granted)
        XCTAssertNil(state.microphoneRequest)
    }

    func testInFlightDownloadKeepsAFailedModelUntilARealReadySignal() throws {
        var state = live(model: .failed(.offline))
        XCTAssertEqual(state.update(.refreshVoiceModel), [.readVoiceModel])
        XCTAssertEqual(state.update(.voiceModelFiles(false)), [])
        XCTAssertEqual(state.localVoiceModel, .failed(.offline))
        XCTAssertEqual(state.update(.voiceModelFiles(true)), [])
        XCTAssertEqual(state.localVoiceModel, .ready)

        state.localVoiceModel = .notDownloaded
        _ = state.update(.downloadVoiceModel)
        let id = try XCTUnwrap(state.modelDownload)
        XCTAssertEqual(state.update(.refresh), [.readAccessibility, .readMicrophone])
        XCTAssertEqual(state.update(.downloadProgress(id, -0.4)), [])
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: 0))
        XCTAssertEqual(state.update(.downloadProgress(id, 1.8)), [])
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: 1))
        state.localVoiceModel = .ready
        XCTAssertEqual(state.update(.downloadSucceeded(id)), [.stopDownloadProgress])
        XCTAssertEqual(state.localVoiceModel, .ready)
        XCTAssertNil(state.modelDownload)
    }

    func testFirstAccessibilityRequestPromptsAndTheNextOpensSettings() {
        var state = live(accessibility: .notGranted)
        XCTAssertEqual(state.update(.requestAccessibility), [.promptAccessibility])
        XCTAssertTrue(state.hasRequestedAccessibility)
        XCTAssertEqual(state.update(.accessibilityPrompted(false)), [])
        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertEqual(state.update(.requestAccessibility), [.openAccessibilitySettings])
        XCTAssertEqual(state.update(.accessibilityPrompted(true)), [])
        XCTAssertEqual(state.accessibility, .granted)
        XCTAssertEqual(state.update(.requestAccessibility), [])
    }

    func testSetupStageWalksPermissionsInOrder() {
        var state = live(accessibility: .notGranted, microphone: .notDetermined, model: .notDownloaded)
        XCTAssertEqual(state.setupStage, .accessibility)
        state.accessibility = .granted
        XCTAssertEqual(state.setupStage, .microphone)
        state.microphone = .restricted
        XCTAssertEqual(state.setupStage, .microphoneSettings)
        state.microphone = .granted
        XCTAssertEqual(state.setupStage, .voiceModel)
        state.localVoiceModel = .downloading(progress: 0.4)
        XCTAssertEqual(state.setupStage, .downloading(progress: 0.4))
        state.localVoiceModel = .failed(.offline)
        XCTAssertEqual(state.setupStage, .failedOffline)
        state.localVoiceModel = .failed(.other)
        XCTAssertEqual(state.setupStage, .failedOther)
        state.localVoiceModel = .ready
        XCTAssertEqual(state.setupStage, .ready)
    }

    func testTeardownIsTerminal() throws {
        var state = live(accessibility: .notGranted, microphone: .notDetermined, model: .notDownloaded)
        _ = state.update(.requestMicrophone)
        _ = state.update(.downloadVoiceModel)
        _ = state.update(.startWatchingVoiceModel(.seconds(2)))
        let microphoneID = try XCTUnwrap(state.microphoneRequest)
        let downloadID = try XCTUnwrap(state.modelDownload)

        XCTAssertEqual(state.update(.teardown), [.cancelTasks])
        XCTAssertTrue(state.isTornDown)
        XCTAssertFalse(state.isWatchingVoiceModel)
        XCTAssertNil(state.microphoneRequest)
        XCTAssertNil(state.modelDownload)

        XCTAssertEqual(state.update(.teardown), [])
        XCTAssertEqual(state.update(.refresh), [])
        XCTAssertEqual(state.update(.requestAccessibility), [])
        XCTAssertEqual(state.update(.microphoneResolved(microphoneID, granted: true)), [])
        XCTAssertEqual(state.update(.downloadSucceeded(downloadID)), [])
        XCTAssertEqual(state.update(.voiceModelBecameReady), [])
        XCTAssertEqual(state.update(.startWatchingVoiceModel(.milliseconds(5))), [])
        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertEqual(state.microphone, .notDetermined)
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        XCTAssertFalse(state.hasRequestedAccessibility)
        XCTAssertFalse(state.isWatchingVoiceModel)
    }

    func testDownloadFailureClassifiesOffline() {
        XCTAssertEqual(VoiceModelDownloadFailure(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(VoiceModelDownloadFailure(URLError(.badURL)), .other)
    }
}
