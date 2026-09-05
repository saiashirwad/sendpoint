import ApplicationServices
import Foundation
import Observation

/// Stable values shown by setup and Settings. Accessibility and microphone
/// status are instant system reads, so neither has an "unknown" case.
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
    /// The Mac had no usable network path to the model host.
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
    case showAccessibilityHelper
    case requestMicrophone
    case openMicrophoneSettings
    case downloadVoiceModel
}

/// A small closure boundary around macOS permission and model APIs.
/// Tests replace it with deterministic closures and never touch TCC.
/// Only the microphone prompt and the model download take time.
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

    static func live() -> PermissionServices {
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
                await VoiceAnnotationService.shared.requestMicrophoneAccess()
            },
            voiceModelFilesExist: {
                LocalVoiceModelFiles.exist()
            },
            downloadVoiceModel: { onProgress in
                try await VoiceAnnotationService.shared.downloadVoiceModel(
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

/// App-owned permission readiness. One instance lives as long as AppDelegate.
@MainActor
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
    @ObservationIgnored private var readinessObserver: NSObjectProtocol?

    var accessibilityAction: PermissionAction? {
        switch accessibility {
        case .granted:
            return nil
        case .notGranted:
            return hasRequestedAccessibility ? .showAccessibilityHelper : .requestAccessibility
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
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.voiceModelBecameReady()
            }
        }
    }

    convenience init() {
        self.init(services: .live())
    }

    /// Re-read everything the system can answer instantly. A microphone
    /// prompt that is still on screen keeps its pre-prompt value until the
    /// user answers it.
    func refresh() {
        guard !isTornDown else { return }
        accessibility = services.accessibilityStatus()
        if microphoneRequestTask == nil {
            microphone = services.microphoneStatus()
        }
        refreshVoiceModel()
    }

    /// Refresh only Accessibility for helper polling.
    func refreshAccessibility() {
        guard !isTornDown else { return }
        accessibility = services.accessibilityStatus()
    }

    /// Re-read the model files without hiding a download or its last failure.
    func refreshVoiceModel() {
        guard !isTornDown, modelDownloadTask == nil else { return }
        if services.voiceModelFilesExist() {
            localVoiceModel = .ready
        } else if case .failed = localVoiceModel {
            return
        } else {
            localVoiceModel = .notDownloaded
        }
    }

    /// Watch the files only while Setup or Settings shows this state.
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

    func requestAccessibility() {
        guard !isTornDown,
              accessibility == .notGranted,
              !hasRequestedAccessibility
        else { return }
        hasRequestedAccessibility = true
        accessibility = services.requestAccessibility() ? .granted : .notGranted
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
                // A capture-time preparation can publish readiness before
                // this caller fails; the ready state stays.
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

    /// Test support. Waits for the microphone prompt and model download.
    func waitForIdle() async {
        await microphoneRequestTask?.value
        await modelDownloadTask?.value
    }

    /// The sole teardown path. Repeated calls do nothing.
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
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
