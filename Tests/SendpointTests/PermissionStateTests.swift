import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class PermissionStateTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    private actor Counter {
        private(set) var value = 0
        func incrementAndGet() -> Int {
            value += 1
            return value
        }
    }

    private actor ModelDownloadGate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var progress: (@Sendable (Double) -> Void)?
        private(set) var count = 0

        func run(progress: @escaping @Sendable (Double) -> Void) async throws {
            count += 1
            self.progress = progress
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func report(_ fraction: Double) {
            progress?(fraction)
        }

        func succeed() {
            continuation?.resume()
            continuation = nil
        }

        func fail(_ error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private final class MicrophoneStatus: @unchecked Sendable {
        var value: MicrophonePermissionState
        init(_ value: MicrophonePermissionState) { self.value = value }
    }

    private actor MicrophoneRequestGate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private(set) var count = 0

        func next() async -> Bool {
            count += 1
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume(with granted: Bool) {
            continuation?.resume(returning: granted)
            continuation = nil
        }
    }

    private func services(
        accessibility: AccessibilityPermissionState = .granted,
        requestAccessibility: Bool = true,
        microphone: MicrophonePermissionState = .granted,
        requestMicrophone: @escaping @Sendable () async -> Bool = { true },
        modelReady: Bool = true,
        modelFilesExist: (@Sendable () -> Bool)? = nil,
        downloadModel: @escaping @Sendable (
            _ onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> Void = { _ in },
        openAccessibilitySettings: @escaping @MainActor @Sendable () -> Void = {},
        openMicrophoneSettings: @escaping @MainActor @Sendable () -> Void = {}
    ) -> PermissionServices {
        PermissionServices(
            accessibilityStatus: { accessibility },
            requestAccessibility: { requestAccessibility },
            microphoneStatus: { microphone },
            requestMicrophone: requestMicrophone,
            voiceModelFilesExist: modelFilesExist ?? { modelReady },
            downloadVoiceModel: downloadModel,
            openAccessibilitySettings: openAccessibilitySettings,
            openMicrophoneSettings: openMicrophoneSettings
        )
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

    func testReadinessMatrixRequiresAccessibilityForTextAndAllVoiceRequirements() {
        let accessibilityStates: [AccessibilityPermissionState] = [.notGranted, .granted]
        let microphoneStates: [MicrophonePermissionState] = [
            .notDetermined, .denied, .restricted, .granted,
        ]

        for accessibility in accessibilityStates {
            for microphone in microphoneStates {
                for modelReady in [false, true] {
                    let state = PermissionController(services: services(
                        accessibility: accessibility,
                        microphone: microphone,
                        modelReady: modelReady
                    ))

                    XCTAssertEqual(state.isTextCaptureReady, accessibility == .granted)
                    state.teardown()
                }
            }
        }
    }

    func testPermissionRequestsPublishSuccessAndDenial() async {
        let granted = PermissionController(services: services(
            accessibility: .notGranted,
            requestAccessibility: true,
            microphone: .notDetermined,
            requestMicrophone: { true }
        ))
        granted.perform(.requestAccessibility)
        granted.perform(.requestMicrophone)
        await granted.waitForIdle()
        XCTAssertEqual(granted.accessibility, .granted)
        XCTAssertEqual(granted.microphone, .granted)
        granted.teardown()

        let denied = PermissionController(services: services(
            accessibility: .notGranted,
            requestAccessibility: false,
            microphone: .notDetermined,
            requestMicrophone: { false }
        ))
        denied.perform(.requestAccessibility)
        denied.perform(.requestMicrophone)
        await denied.waitForIdle()
        XCTAssertEqual(denied.accessibility, .notGranted)
        XCTAssertEqual(denied.microphone, .denied)
        denied.teardown()
    }

    func testAccessibilityRequestOpensSettingsOnlyWhenStillDenied() {
        final class OpenCount: @unchecked Sendable {
            var value = 0
        }
        let opened = OpenCount()
        let granted = PermissionController(services: services(
            accessibility: .notGranted,
            requestAccessibility: true,
            openAccessibilitySettings: { opened.value += 1 }
        ))
        granted.perform(.requestAccessibility)
        XCTAssertEqual(granted.accessibility, .granted)
        XCTAssertEqual(opened.value, 0)
        granted.teardown()

        let denied = PermissionController(services: services(
            accessibility: .notGranted,
            requestAccessibility: false,
            openAccessibilitySettings: { opened.value += 1 }
        ))
        denied.perform(.requestAccessibility)
        XCTAssertEqual(denied.accessibility, .notGranted)
        XCTAssertEqual(opened.value, 0)
        denied.perform(.requestAccessibility)
        XCTAssertEqual(opened.value, 1)
        denied.teardown()
    }

    func testRefreshDuringMicrophonePromptKeepsPrePromptValue() async {
        let gate = MicrophoneRequestGate()
        let reported = MicrophoneStatus(.notDetermined)
        let state = PermissionController(services: PermissionServices(
            accessibilityStatus: { .granted },
            requestAccessibility: { true },
            microphoneStatus: { reported.value },
            requestMicrophone: { await gate.next() },
            voiceModelFilesExist: { true },
            downloadVoiceModel: { _ in },
            openAccessibilitySettings: {},
            openMicrophoneSettings: {}
        ))

        state.perform(.requestMicrophone)
        await waitUntil { await gate.count == 1 }
        reported.value = .denied
        state.perform(.requestMicrophone)
        state.refresh()
        XCTAssertEqual(state.microphone, .notDetermined)

        await gate.resume(with: true)
        await state.waitForIdle()
        XCTAssertEqual(state.microphone, .granted)
        let promptCount = await gate.count
        XCTAssertEqual(promptCount, 1)
        state.teardown()
    }

    func testModelDownloadFailureCanRetryAndSucceed() async {
        let attempts = Counter()
        let state = PermissionController(services: services(
            modelReady: false,
            downloadModel: { _ in
                let attempt = await attempts.incrementAndGet()
                if attempt == 1 { throw TestError.failed }
            }
        ))

        state.perform(.downloadVoiceModel)
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .failed(.other))

        state.perform(.downloadVoiceModel)
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testRefreshDuringDownloadKeepsDownloadingState() async {
        let gate = ModelDownloadGate()
        let state = PermissionController(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))

        state.perform(.downloadVoiceModel)
        state.perform(.downloadVoiceModel)
        await waitUntil { await gate.count == 1 }
        state.refresh()

        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        XCTAssertNil(state.state.localVoiceModelAction)

        await gate.succeed()
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        let downloadCount = await gate.count
        XCTAssertEqual(downloadCount, 1)
        state.teardown()
    }

    func testReadyNotificationWinsOverOwnedDownloadFailure() async {
        let gate = ModelDownloadGate()
        let state = PermissionController(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))
        state.perform(.downloadVoiceModel)
        await waitUntil { await gate.count == 1 }

        NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
        XCTAssertEqual(state.localVoiceModel, .ready)
        await gate.fail(TestError.failed)
        await state.waitForIdle()

        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testVoiceModelReadyNotificationFromBackgroundThreadIsHandledOnMain() async {
        let state = PermissionController(services: services(modelReady: false))
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)

        await Task.detached {
            NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
        }.value
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testVisibleWatcherPicksUpDiskChangesBothWays() async {
        let files = Locked(false)
        let state = PermissionController(services: services(
            modelFilesExist: { files.value }
        ))
        let watcher = Task {
            await state.watchVoiceModel(interval: .milliseconds(1))
        }

        files.value = true
        await waitUntil { state.localVoiceModel == .ready }
        files.value = false
        await waitUntil { state.localVoiceModel == .notDownloaded }

        watcher.cancel()
        await watcher.value
        state.teardown()
    }

    func testFailedDownloadSurvivesRefreshAndRecoversWhenFilesAppear() async {
        let files = Locked(false)
        let state = PermissionController(services: services(
            modelFilesExist: { files.value },
            downloadModel: { _ in throw TestError.failed }
        ))

        state.perform(.downloadVoiceModel)
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .failed(.other))

        state.refresh()
        XCTAssertEqual(state.localVoiceModel, .failed(.other))

        files.value = true
        state.refreshVoiceModel()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testDownloadProgressIsClampedAndLateProgressIsRejected() async {
        let gate = ModelDownloadGate()
        let state = PermissionController(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))
        state.perform(.downloadVoiceModel)
        await waitUntil { await gate.count == 1 }

        await gate.report(-0.25)
        await waitUntil { state.localVoiceModel == .downloading(progress: 0) }
        await gate.report(1.25)
        await waitUntil { state.localVoiceModel == .downloading(progress: 1) }

        await gate.succeed()
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        await gate.report(0.5)
        await Task.yield()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testActionsRouteFromLivePermissionStates() {
        let state = PermissionController(services: services(
            accessibility: .notGranted,
            requestAccessibility: false,
            microphone: .notDetermined,
            modelReady: false
        ))

        XCTAssertEqual(state.state.accessibilityAction, .requestAccessibility)
        XCTAssertEqual(state.state.microphoneAction, .requestMicrophone)
        XCTAssertEqual(state.state.localVoiceModelAction, .downloadVoiceModel)

        state.perform(.requestAccessibility)
        XCTAssertEqual(state.state.accessibilityAction, .requestAccessibility)
        state.teardown()

        let blocked = PermissionController(services: services(
            microphone: .restricted,
            modelReady: true
        ))
        XCTAssertNil(blocked.state.accessibilityAction)
        XCTAssertEqual(blocked.state.microphoneAction, .openMicrophoneSettings)
        XCTAssertNil(blocked.state.localVoiceModelAction)
        blocked.teardown()
    }

    func testSetupAndCatalogShareActionsAcrossEveryStage() {
        let cases: [(PermissionState, Int, PermissionAction?)] = [
            (PermissionState(accessibility: .notGranted, microphone: .notDetermined,
                             localVoiceModel: .notDownloaded), 0, .requestAccessibility),
            (PermissionState(accessibility: .granted, microphone: .notDetermined,
                             localVoiceModel: .notDownloaded), 1, .requestMicrophone),
            (PermissionState(accessibility: .granted, microphone: .denied,
                             localVoiceModel: .notDownloaded), 1, .openMicrophoneSettings),
            (PermissionState(accessibility: .granted, microphone: .restricted,
                             localVoiceModel: .notDownloaded), 1, .openMicrophoneSettings),
            (PermissionState(accessibility: .granted, microphone: .granted,
                             localVoiceModel: .notDownloaded), 2, .downloadVoiceModel),
            (PermissionState(accessibility: .granted, microphone: .granted,
                             localVoiceModel: .failed(.offline)), 2, .downloadVoiceModel),
            (PermissionState(accessibility: .granted, microphone: .granted,
                             localVoiceModel: .failed(.other)), 2, .downloadVoiceModel),
            (PermissionState(accessibility: .granted, microphone: .granted,
                             localVoiceModel: .downloading(progress: 0.4)), 2, nil),
            (PermissionState(accessibility: .granted, microphone: .granted,
                             localVoiceModel: .ready), 2, nil),
        ]
        for (state, row, action) in cases {
            XCTAssertEqual(state.setupStage.action, action)
            let item = PermissionCatalog.items(state: state)[row]
            XCTAssertEqual(item.action, action)
            XCTAssertEqual(item.actionTitle != nil, action != nil)
            XCTAssertEqual(state.setupStage.actionTitle != nil, action != nil)
        }
    }

    func testCatalogAndSetupDispatchDriveTheSameReadiness() async {
        let controller = PermissionController(services: services(
            accessibility: .notGranted, microphone: .notDetermined, modelReady: false
        ))
        defer { controller.teardown() }
        let accessibility = PermissionCatalog.items(state: controller.state)[0]
        XCTAssertEqual(accessibility.action, controller.setupStage.action)
        controller.perform(accessibility.action)
        XCTAssertEqual(controller.setupStage, .microphone)
        controller.perform(controller.setupStage.action)
        await controller.waitForIdle()
        XCTAssertEqual(controller.setupStage, .voiceModel)
        let model = PermissionCatalog.items(state: controller.state)[2]
        XCTAssertEqual(model.action, controller.setupStage.action)
        controller.perform(model.action)
        XCTAssertEqual(controller.setupStage, .downloading(progress: nil))
        XCTAssertNil(PermissionCatalog.items(state: controller.state)[2].action)
        await controller.waitForIdle()
        XCTAssertEqual(controller.setupStage, .ready)
    }

    func testDispatcherRejectsAStaleSettingsActionAfterExternalGrant() {
        let reported = MicrophoneStatus(.denied)
        var opened = 0
        var boundary = services(openMicrophoneSettings: { opened += 1 })
        boundary.microphoneStatus = { reported.value }
        let controller = PermissionController(services: boundary)
        defer { controller.teardown() }
        let stale = PermissionCatalog.items(state: controller.state)[1].action
        XCTAssertEqual(stale, .openMicrophoneSettings)
        controller.perform(stale)
        XCTAssertEqual(opened, 1)
        reported.value = .granted
        controller.refresh()
        XCTAssertEqual(controller.setupStage, .ready)
        controller.perform(stale)
        controller.perform(nil)
        XCTAssertEqual(opened, 1)
    }

    func testTeardownIsIdempotentAndIgnoresLateWork() async {
        let gate = MicrophoneRequestGate()
        let state = PermissionController(services: services(
            accessibility: .notGranted,
            microphone: .notDetermined,
            requestMicrophone: { await gate.next() },
            modelReady: false
        ))

        state.perform(.requestMicrophone)
        await waitUntil { await gate.count == 1 }
        state.teardown()
        state.teardown()
        await gate.resume(with: true)
        await Task.yield()
        XCTAssertEqual(state.microphone, .notDetermined)

        state.refresh()
        state.perform(.requestAccessibility)
        state.perform(.downloadVoiceModel)
        NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
        await state.waitForIdle()
        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertFalse(state.hasRequestedAccessibility)
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)
    }
}
