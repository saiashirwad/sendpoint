import ApplicationServices
import Foundation
import Observation
import SendpointDomain

struct PermissionServices: Sendable {
    var accessibilityStatus: @MainActor @Sendable () -> AccessibilityPermissionState
    var requestAccessibility: @MainActor @Sendable () -> Bool
    var microphoneStatus: @MainActor @Sendable () -> MicrophonePermissionState
    var requestMicrophone: @Sendable () async -> Bool
    var voiceModelFilesExist: @Sendable () -> Bool
    var downloadVoiceModel: @Sendable (
        _ onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Void
    var openAccessibilitySettings: @MainActor @Sendable () -> Void
    var openMicrophoneSettings: @MainActor @Sendable () -> Void

    static func live(transcriber: any VoiceTranscribing) -> PermissionServices {
        PermissionServices(
            accessibilityStatus: {
                AXIsProcessTrusted() ? .granted : .notGranted
            },
            requestAccessibility: {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            },
            microphoneStatus: {
                PermissionCheck.microphonePermissionState
            },
            requestMicrophone: {
                await PermissionCheck.requestMicrophoneAccess()
            },
            voiceModelFilesExist: {
                LocalVoiceModelFiles.exist()
            },
            downloadVoiceModel: { onProgress in
                try await transcriber.prepare(onProgress: onProgress)
            },
            openAccessibilitySettings: {
                PermissionCheck.openAccessibilitySettings()
            },
            openMicrophoneSettings: {
                PermissionCheck.openMicrophoneSettings()
            }
        )
    }
}

@Observable
final class PermissionController {
    private(set) var state: PermissionState
    @ObservationIgnored private let services: PermissionServices
    @ObservationIgnored private var microphoneTask: Task<Void, Never>?
    @ObservationIgnored private var modelDownloadTask: Task<Void, Never>?
    @ObservationIgnored private var voiceModelWatchTask: Task<Void, Never>?
    @ObservationIgnored private let downloadProgress = LatestValuePump<Double>()
    @ObservationIgnored private var readinessObserver: NSObjectProtocol?
    @ObservationIgnored private var pending: [PermissionEvent] = []
    @ObservationIgnored private var isDraining = false

    var accessibility: AccessibilityPermissionState { state.accessibility }
    var microphone: MicrophonePermissionState { state.microphone }
    var localVoiceModel: LocalVoiceModelState { state.localVoiceModel }
    var hasRequestedAccessibility: Bool { state.hasRequestedAccessibility }
    var isWatchingVoiceModel: Bool { state.isWatchingVoiceModel }
    var isTextCaptureReady: Bool { state.isTextCaptureReady }
    var accessibilityAction: PermissionEvent? { state.accessibilityAction }
    var microphoneAction: PermissionEvent? { state.microphoneAction }
    var localVoiceModelAction: PermissionEvent? { state.localVoiceModelAction }
    var setupStage: SetupHeroStage { SetupHeroStage(state.setupStage) }

    init(services: PermissionServices) {
        self.services = services
        state = PermissionState(
            accessibility: services.accessibilityStatus(),
            microphone: services.microphoneStatus(),
            localVoiceModel: services.voiceModelFilesExist() ? .ready : .notDownloaded
        )
        readinessObserver = NotificationCenter.default.addObserver(
            forName: .voiceModelDidBecomeReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.voiceModelBecameReady()
            }
        }
    }

    func refresh() { send(.refresh) }
    func refreshAccessibility() { send(.refreshAccessibility) }
    func refreshVoiceModel() { send(.refreshVoiceModel) }
    func requestAccessibility() { send(.requestAccessibility) }
    func requestMicrophone() { send(.requestMicrophone) }
    func downloadModel() { send(.downloadVoiceModel) }
    func openMicrophoneSettings() { send(.openMicrophoneSettings) }

    func startWatchingVoiceModel(interval: Duration = .seconds(2)) {
        send(.startWatchingVoiceModel(interval))
    }

    func stopWatchingVoiceModel() { send(.stopWatchingVoiceModel) }
    func voiceModelBecameReady() { send(.voiceModelBecameReady) }

    func watchVoiceModel(interval: Duration = .seconds(2)) async {
        while !state.isTornDown, !Task.isCancelled {
            refreshVoiceModel()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    func waitForIdle() async {
        await microphoneTask?.value
        await modelDownloadTask?.value
    }

    func teardown() {
        guard !state.isTornDown else { return }
        send(.teardown)
    }

    private func send(_ event: PermissionEvent) {
        pending.append(event)
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            var next = state
            let effects = next.update(pending.removeFirst())
            if next != state { state = next }
            run(effects)
        }
        isDraining = false
    }

    private func run(_ effects: [PermissionEffect]) {
        for effect in effects {
            switch effect {
            case .readAccessibility:
                send(.accessibilityStatus(services.accessibilityStatus()))
            case .readMicrophone:
                send(.microphoneStatus(services.microphoneStatus()))
            case .readVoiceModel:
                send(.voiceModelFiles(services.voiceModelFilesExist()))
            case .promptAccessibility:
                send(.accessibilityPrompted(services.requestAccessibility()))
            case .openAccessibilitySettings:
                services.openAccessibilitySettings()
            case .openMicrophoneSettings:
                services.openMicrophoneSettings()
            case let .requestMicrophone(id):
                microphoneTask = Task { [weak self, services] in
                    let granted: Bool
                    do {
                        try Task.checkCancellation()
                        granted = await services.requestMicrophone()
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    guard let self, self.state.microphoneRequest == id else { return }
                    self.microphoneTask = nil
                    self.send(.microphoneResolved(id, granted: granted))
                }
            case let .downloadModel(id):
                let continuation = downloadProgress.start { [weak self] fraction in
                    self?.send(.downloadProgress(id, fraction))
                }
                let report: @Sendable (Double) -> Void = { continuation.yield($0) }
                modelDownloadTask = Task { [weak self, services] in
                    do {
                        try Task.checkCancellation()
                        try await services.downloadVoiceModel(report)
                        try Task.checkCancellation()
                        guard let self, self.state.modelDownload == id else { return }
                        self.modelDownloadTask = nil
                        self.send(.downloadSucceeded(id))
                    } catch is CancellationError {
                    } catch {
                        guard !Task.isCancelled, let self, self.state.modelDownload == id else { return }
                        self.modelDownloadTask = nil
                        self.send(.downloadFailed(id, VoiceModelDownloadFailure(error)))
                    }
                }
            case .stopDownloadProgress:
                downloadProgress.stop()
            case let .watchVoiceModel(interval):
                guard voiceModelWatchTask == nil else { return }
                voiceModelWatchTask = Task { [weak self] in
                    await self?.watchVoiceModel(interval: interval)
                }
            case .stopWatchingVoiceModel:
                voiceModelWatchTask?.cancel()
                voiceModelWatchTask = nil
            case .cancelTasks:
                voiceModelWatchTask?.cancel()
                voiceModelWatchTask = nil
                microphoneTask?.cancel()
                microphoneTask = nil
                modelDownloadTask?.cancel()
                modelDownloadTask = nil
                downloadProgress.stop()
                if let readinessObserver {
                    NotificationCenter.default.removeObserver(readinessObserver)
                    self.readinessObserver = nil
                }
            }
        }
    }
}
