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

    private final class BoolBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: Bool

        init(_ value: Bool) {
            storedValue = value
        }

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedValue
            }
            set {
                lock.lock()
                storedValue = newValue
                lock.unlock()
            }
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
        ) async throws -> Void = { _ in }
    ) -> PermissionServices {
        PermissionServices(
            accessibilityStatus: { accessibility },
            requestAccessibility: { requestAccessibility },
            microphoneStatus: { microphone },
            requestMicrophone: requestMicrophone,
            voiceModelFilesExist: modelFilesExist ?? { modelReady },
            downloadVoiceModel: downloadModel,
            openAccessibilitySettings: {},
            openMicrophoneSettings: {}
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
                    let state = PermissionState(services: services(
                        accessibility: accessibility,
                        microphone: microphone,
                        modelReady: modelReady
                    ))

                    XCTAssertEqual(state.isTextCaptureReady, accessibility == .granted)
                    XCTAssertEqual(
                        state.isVoiceReady,
                        accessibility == .granted && microphone == .granted && modelReady
                    )
                    state.teardown()
                }
            }
        }
    }

    func testInitAndRefreshPublishServiceValues() {
        let state = PermissionState(services: services(
            accessibility: .notGranted,
            microphone: .restricted,
            modelReady: false
        ))

        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertEqual(state.microphone, .restricted)
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)

        state.refresh()
        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertEqual(state.microphone, .restricted)
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)
        state.teardown()
    }

    func testPermissionRequestsPublishSuccessAndDenial() async {
        let granted = PermissionState(services: services(
            accessibility: .notGranted,
            requestAccessibility: true,
            microphone: .notDetermined,
            requestMicrophone: { true }
        ))
        granted.requestAccessibility()
        granted.requestMicrophone()
        await granted.waitForIdle()
        XCTAssertEqual(granted.accessibility, .granted)
        XCTAssertEqual(granted.microphone, .granted)
        granted.teardown()

        let denied = PermissionState(services: services(
            accessibility: .notGranted,
            requestAccessibility: false,
            microphone: .notDetermined,
            requestMicrophone: { false }
        ))
        denied.requestAccessibility()
        denied.requestMicrophone()
        await denied.waitForIdle()
        XCTAssertEqual(denied.accessibility, .notGranted)
        XCTAssertEqual(denied.microphone, .denied)
        denied.teardown()
    }

    func testRefreshDuringMicrophonePromptKeepsPrePromptValue() async {
        let gate = MicrophoneRequestGate()
        let state = PermissionState(services: services(
            microphone: .notDetermined,
            requestMicrophone: { await gate.next() }
        ))

        state.requestMicrophone()
        await waitUntil { await gate.count == 1 }
        state.requestMicrophone()
        state.refresh()
        XCTAssertEqual(state.microphone, .notDetermined)

        await gate.resume(with: true)
        await state.waitForIdle()
        XCTAssertEqual(state.microphone, .granted)
        let promptCount = await gate.count
        XCTAssertEqual(promptCount, 1)
        state.teardown()
    }

    func testLocalVoiceModelReadinessIncludesFilesPersistedAcrossLaunch() async {
        let downloaded = LocalVoiceTranscriber(modelsAreDownloaded: { true })
        let absent = LocalVoiceTranscriber(modelsAreDownloaded: { false })

        let downloadedIsReady = await downloaded.isReady()
        let absentIsReady = await absent.isReady()

        XCTAssertTrue(downloadedIsReady)
        XCTAssertFalse(absentIsReady)
    }

    func testModelDownloadFailureCanRetryAndSucceed() async {
        let attempts = Counter()
        let state = PermissionState(services: services(
            modelReady: false,
            downloadModel: { _ in
                let attempt = await attempts.incrementAndGet()
                if attempt == 1 { throw TestError.failed }
            }
        ))

        state.downloadModel()
        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .failed(.other))

        state.downloadModel()
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testRefreshDuringDownloadKeepsDownloadingState() async {
        let gate = ModelDownloadGate()
        let state = PermissionState(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))

        state.downloadModel()
        state.downloadModel()
        await waitUntil { await gate.count == 1 }
        state.refresh()

        XCTAssertEqual(state.localVoiceModel, .downloading(progress: nil))
        XCTAssertNil(state.localVoiceModelAction)

        await gate.succeed()
        await state.waitForIdle()
        XCTAssertEqual(state.localVoiceModel, .ready)
        let downloadCount = await gate.count
        XCTAssertEqual(downloadCount, 1)
        state.teardown()
    }

    func testModelReadyNotificationPublishesCaptureTimePreparation() {
        let state = PermissionState(services: services(modelReady: false))
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)

        NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)

        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testReadyNotificationWinsOverOwnedDownloadFailure() async {
        let gate = ModelDownloadGate()
        let state = PermissionState(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))
        state.downloadModel()
        await waitUntil { await gate.count == 1 }

        NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
        XCTAssertEqual(state.localVoiceModel, .ready)
        await gate.fail(TestError.failed)
        await state.waitForIdle()

        XCTAssertEqual(state.localVoiceModel, .ready)
        state.teardown()
    }

    func testVisibleWatcherPicksUpDiskChangesBothWays() async {
        let files = BoolBox(false)
        let state = PermissionState(services: services(
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
        let files = BoolBox(false)
        let state = PermissionState(services: services(
            modelFilesExist: { files.value },
            downloadModel: { _ in throw TestError.failed }
        ))

        state.downloadModel()
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
        let state = PermissionState(services: services(
            modelReady: false,
            downloadModel: { progress in try await gate.run(progress: progress) }
        ))
        state.downloadModel()
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
        let state = PermissionState(services: services(
            accessibility: .notGranted,
            requestAccessibility: false,
            microphone: .notDetermined,
            modelReady: false
        ))

        XCTAssertEqual(state.accessibilityAction, .requestAccessibility)
        XCTAssertEqual(state.microphoneAction, .requestMicrophone)
        XCTAssertEqual(state.localVoiceModelAction, .downloadVoiceModel)

        state.requestAccessibility()
        XCTAssertEqual(state.accessibilityAction, .showAccessibilityHelper)
        state.teardown()

        let blocked = PermissionState(services: services(
            microphone: .restricted,
            modelReady: true
        ))
        XCTAssertNil(blocked.accessibilityAction)
        XCTAssertEqual(blocked.microphoneAction, .openMicrophoneSettings)
        XCTAssertNil(blocked.localVoiceModelAction)
        blocked.teardown()
    }

    func testTeardownIsIdempotentAndIgnoresLateWork() async {
        let gate = MicrophoneRequestGate()
        let state = PermissionState(services: services(
            accessibility: .notGranted,
            microphone: .notDetermined,
            requestMicrophone: { await gate.next() },
            modelReady: false
        ))

        state.requestMicrophone()
        await waitUntil { await gate.count == 1 }
        state.teardown()
        state.teardown()
        await gate.resume(with: true)
        await Task.yield()
        XCTAssertEqual(state.microphone, .notDetermined)

        state.refresh()
        state.requestAccessibility()
        state.downloadModel()
        NotificationCenter.default.post(name: .voiceModelDidBecomeReady, object: nil)
        await state.waitForIdle()
        XCTAssertEqual(state.accessibility, .notGranted)
        XCTAssertFalse(state.hasRequestedAccessibility)
        XCTAssertEqual(state.localVoiceModel, .notDownloaded)
    }
}
