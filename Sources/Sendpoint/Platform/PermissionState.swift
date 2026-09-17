import ApplicationServices
import Foundation
import Observation

enum AccessibilityPermissionState: Equatable, Sendable {
    case notGranted
    case granted
}

enum MicrophonePermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case granted
}

enum LocalVoiceModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double?)
    case ready
    case failed(VoiceModelDownloadFailure)
}

enum VoiceModelDownloadFailure: Equatable, Sendable {
    case offline
    case other

    init(_ error: Error) {
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff,
        ]
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            self = .offline
        } else {
            self = .other
        }
    }
}

enum PermissionAction: Equatable, Sendable {
    case requestAccessibility
    case requestMicrophone
    case openMicrophoneSettings
    case downloadVoiceModel
}

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

    static func live(voiceService: VoiceNoteService) -> PermissionServices {
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
                await voiceService.requestMicrophoneAccess()
            },
            voiceModelFilesExist: {
                LocalVoiceModelFiles.exist()
            },
            downloadVoiceModel: { onProgress in
                try await voiceService.downloadVoiceModel(
                    onProgress: onProgress
                )
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
final class PermissionState {
    private let services: PermissionServices
    private var isTornDown = false

    private(set) var accessibility: AccessibilityPermissionState
    private(set) var microphone: MicrophonePermissionState
    private(set) var localVoiceModel: LocalVoiceModelState
    private(set) var hasRequestedAccessibility = false

    @ObservationIgnored private var microphoneRequestTask: Task<Void, Never>?
    @ObservationIgnored private var modelDownloadTask: Task<Void, Never>?
    @ObservationIgnored private var voiceModelWatchTask: Task<Void, Never>?
    @ObservationIgnored private var voiceModelWatchers = 0
    @ObservationIgnored private var readinessObserver: NSObjectProtocol?

    var accessibilityAction: PermissionAction? {
        switch accessibility {
        case .granted:
            return nil
        case .notGranted:
            return .requestAccessibility
        }
    }

    var microphoneAction: PermissionAction? {
        switch microphone {
        case .granted:
            return nil
        case .notDetermined:
            return .requestMicrophone
        case .denied, .restricted:
            return .openMicrophoneSettings
        }
    }

    var localVoiceModelAction: PermissionAction? {
        switch localVoiceModel {
        case .downloading, .ready:
            return nil
        case .notDownloaded, .failed:
            return .downloadVoiceModel
        }
    }

    var isTextCaptureReady: Bool {
        accessibility == .granted
    }

    var isVoiceReady: Bool {
        isTextCaptureReady
            && microphone == .granted
            && localVoiceModel == .ready
    }

    init(services: PermissionServices) {
        self.services = services
        accessibility = services.accessibilityStatus()
        microphone = services.microphoneStatus()
        localVoiceModel = services.voiceModelFilesExist() ? .ready : .notDownloaded
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

    func refresh() {
        guard !isTornDown else { return }
        refreshAccessibility()
        if microphoneRequestTask == nil {
            let status = services.microphoneStatus()
            if microphone != status { microphone = status }
        }
        refreshVoiceModel()
    }

    func refreshAccessibility() {
        guard !isTornDown else { return }
        let status = services.accessibilityStatus()
        if accessibility != status { accessibility = status }
    }

    func refreshVoiceModel() {
        guard !isTornDown, modelDownloadTask == nil else { return }
        if services.voiceModelFilesExist() {
            if localVoiceModel != .ready { localVoiceModel = .ready }
        } else if case .failed = localVoiceModel {
            return
        } else {
            localVoiceModel = .notDownloaded
        }
    }

    func watchVoiceModel(interval: Duration = .seconds(2)) async {
        while !isTornDown, !Task.isCancelled {
            refreshVoiceModel()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    var isWatchingVoiceModel: Bool { voiceModelWatchTask != nil }

    func startWatchingVoiceModel(interval: Duration = .seconds(2)) {
        guard !isTornDown else { return }
        voiceModelWatchers += 1
        guard voiceModelWatchTask == nil else { return }
        voiceModelWatchTask = Task { [weak self] in
            await self?.watchVoiceModel(interval: interval)
        }
    }

    func stopWatchingVoiceModel() {
        guard voiceModelWatchers > 0 else { return }
        voiceModelWatchers -= 1
        if voiceModelWatchers == 0 {
            voiceModelWatchTask?.cancel()
            voiceModelWatchTask = nil
        }
    }

    func requestAccessibility() {
        guard !isTornDown, accessibility == .notGranted else { return }
        if !hasRequestedAccessibility {
            hasRequestedAccessibility = true
            accessibility = services.requestAccessibility() ? .granted : .notGranted
            return
        }
        services.openAccessibilitySettings()
    }

    func requestMicrophone() {
        guard !isTornDown, microphone == .notDetermined, microphoneRequestTask == nil else { return }
        let services = services
        microphoneRequestTask = Task { [weak self] in
            let granted = await services.requestMicrophone()
            guard !Task.isCancelled, let self else { return }
            self.microphoneRequestTask = nil
            self.microphone = granted ? .granted : .denied
        }
    }

    func downloadModel() {
        guard !isTornDown,
              modelDownloadTask == nil,
              localVoiceModelAction == .downloadVoiceModel
        else { return }
        let services = services
        localVoiceModel = .downloading(progress: nil)

        let reportProgress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.reportModelDownloadProgress(fraction) }
        }

        modelDownloadTask = Task { [weak self] in
            do {
                try await services.downloadVoiceModel(reportProgress)
                guard !Task.isCancelled, let self else { return }
                self.modelDownloadTask = nil
                self.localVoiceModel = .ready
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.modelDownloadTask = nil
                if case .downloading = self.localVoiceModel {
                    self.localVoiceModel = .failed(VoiceModelDownloadFailure(error))
                }
            }
        }
    }

    func voiceModelBecameReady() {
        guard !isTornDown else { return }
        localVoiceModel = .ready
    }

    func openAccessibilitySettings() {
        guard !isTornDown else { return }
        services.openAccessibilitySettings()
    }

    func openMicrophoneSettings() {
        guard !isTornDown else { return }
        services.openMicrophoneSettings()
    }

    func waitForIdle() async {
        await microphoneRequestTask?.value
        await modelDownloadTask?.value
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        voiceModelWatchTask?.cancel()
        voiceModelWatchTask = nil
        voiceModelWatchers = 0
        microphoneRequestTask?.cancel()
        modelDownloadTask?.cancel()
        microphoneRequestTask = nil
        modelDownloadTask = nil
        if let readinessObserver {
            NotificationCenter.default.removeObserver(readinessObserver)
            self.readinessObserver = nil
        }
    }

    private func reportModelDownloadProgress(_ fraction: Double) {
        guard !isTornDown, case .downloading = localVoiceModel else { return }
        localVoiceModel = .downloading(progress: min(max(fraction, 0), 1))
    }
}
