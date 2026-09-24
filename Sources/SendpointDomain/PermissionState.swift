import Foundation

public nonisolated enum AccessibilityPermissionState: Equatable, Sendable {
    case notGranted
    case granted
}

public nonisolated enum MicrophonePermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case granted
}

public nonisolated enum LocalVoiceModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double?)
    case ready
    case failed(VoiceModelDownloadFailure)
}

public nonisolated enum VoiceModelDownloadFailure: Equatable, Sendable {
    case offline
    case other

    public init(_ error: Error) {
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

public nonisolated enum PermissionSetupStage: Equatable, Sendable {
    case accessibility
    case microphone
    case microphoneSettings
    case voiceModel
    case downloading(progress: Double?)
    case failedOffline
    case failedOther
    case ready
}

public nonisolated enum PermissionEvent: Equatable, Sendable {
    case refresh
    case refreshAccessibility
    case refreshVoiceModel
    case accessibilityStatus(AccessibilityPermissionState)
    case microphoneStatus(MicrophonePermissionState)
    case voiceModelFiles(Bool)
    case requestAccessibility
    case accessibilityPrompted(Bool)
    case requestMicrophone
    case microphoneResolved(UUID, granted: Bool)
    case openMicrophoneSettings
    case downloadVoiceModel
    case downloadProgress(UUID, Double)
    case downloadSucceeded(UUID)
    case downloadFailed(UUID, VoiceModelDownloadFailure)
    case voiceModelBecameReady
    case startWatchingVoiceModel(Duration)
    case stopWatchingVoiceModel
    case teardown
}

public nonisolated enum PermissionEffect: Equatable, Sendable {
    case readAccessibility
    case readMicrophone
    case readVoiceModel
    case promptAccessibility
    case openAccessibilitySettings
    case openMicrophoneSettings
    case requestMicrophone(UUID)
    case downloadModel(UUID)
    case stopDownloadProgress
    case watchVoiceModel(Duration)
    case stopWatchingVoiceModel
    case cancelTasks
}

public nonisolated struct PermissionState: Equatable, Sendable {
    public enum Lifecycle: Equatable, Sendable {
        case live
        case tornDown
    }

    public var lifecycle: Lifecycle = .live
    public var accessibility: AccessibilityPermissionState
    public var microphone: MicrophonePermissionState
    public var localVoiceModel: LocalVoiceModelState
    public var hasRequestedAccessibility: Bool
    public var microphoneRequest: UUID?
    public var modelDownload: UUID?
    public var isWatchingVoiceModel: Bool

    public init(
        accessibility: AccessibilityPermissionState,
        microphone: MicrophonePermissionState,
        localVoiceModel: LocalVoiceModelState,
        hasRequestedAccessibility: Bool = false,
        microphoneRequest: UUID? = nil,
        modelDownload: UUID? = nil,
        isWatchingVoiceModel: Bool = false
    ) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.localVoiceModel = localVoiceModel
        self.hasRequestedAccessibility = hasRequestedAccessibility
        self.microphoneRequest = microphoneRequest
        self.modelDownload = modelDownload
        self.isWatchingVoiceModel = isWatchingVoiceModel
    }

    public var isTornDown: Bool { lifecycle == .tornDown }

    public var accessibilityAction: PermissionEvent? {
        switch accessibility {
        case .granted: nil
        case .notGranted: .requestAccessibility
        }
    }

    public var microphoneAction: PermissionEvent? {
        switch microphone {
        case .granted: nil
        case .notDetermined: .requestMicrophone
        case .denied, .restricted: .openMicrophoneSettings
        }
    }

    public var localVoiceModelAction: PermissionEvent? {
        switch localVoiceModel {
        case .downloading, .ready: nil
        case .notDownloaded, .failed: .downloadVoiceModel
        }
    }

    public var isTextCaptureReady: Bool { accessibility == .granted }

    public var setupStage: PermissionSetupStage {
        if accessibility != .granted { return .accessibility }
        switch microphone {
        case .notDetermined: return .microphone
        case .denied, .restricted: return .microphoneSettings
        case .granted: break
        }
        switch localVoiceModel {
        case .notDownloaded: return .voiceModel
        case let .downloading(progress): return .downloading(progress: progress)
        case .failed(.offline): return .failedOffline
        case .failed(.other): return .failedOther
        case .ready: return .ready
        }
    }

    public mutating func update(_ event: PermissionEvent) -> [PermissionEffect] {
        guard !isTornDown else { return [] }
        switch event {
        case .teardown:
            lifecycle = .tornDown
            isWatchingVoiceModel = false
            microphoneRequest = nil
            modelDownload = nil
            return [.cancelTasks]
        case .refresh:
            var effects: [PermissionEffect] = [.readAccessibility]
            if microphoneRequest == nil { effects.append(.readMicrophone) }
            if modelDownload == nil { effects.append(.readVoiceModel) }
            return effects
        case .refreshAccessibility:
            return [.readAccessibility]
        case .refreshVoiceModel:
            guard modelDownload == nil else { return [] }
            return [.readVoiceModel]
        case let .accessibilityStatus(status):
            accessibility = status
            return []
        case let .microphoneStatus(status):
            guard microphoneRequest == nil else { return [] }
            microphone = status
            return []
        case let .voiceModelFiles(exist):
            guard modelDownload == nil else { return [] }
            if exist {
                localVoiceModel = .ready
            } else if case .failed = localVoiceModel {
                return []
            } else {
                localVoiceModel = .notDownloaded
            }
            return []
        case .requestAccessibility:
            guard accessibility == .notGranted else { return [] }
            if !hasRequestedAccessibility {
                hasRequestedAccessibility = true
                return [.promptAccessibility]
            }
            return [.openAccessibilitySettings]
        case let .accessibilityPrompted(granted):
            accessibility = granted ? .granted : .notGranted
            return []
        case .requestMicrophone:
            guard microphone == .notDetermined, microphoneRequest == nil else { return [] }
            let id = UUID()
            microphoneRequest = id
            return [.requestMicrophone(id)]
        case let .microphoneResolved(id, granted):
            guard microphoneRequest == id else { return [] }
            microphoneRequest = nil
            microphone = granted ? .granted : .denied
            return []
        case .openMicrophoneSettings:
            return [.openMicrophoneSettings]
        case .downloadVoiceModel:
            guard modelDownload == nil else { return [] }
            switch localVoiceModel {
            case .notDownloaded, .failed:
                let id = UUID()
                modelDownload = id
                localVoiceModel = .downloading(progress: nil)
                return [.downloadModel(id)]
            case .downloading, .ready:
                return []
            }
        case let .downloadProgress(id, fraction):
            guard modelDownload == id, case .downloading = localVoiceModel else { return [] }
            localVoiceModel = .downloading(progress: min(max(fraction, 0), 1))
            return []
        case let .downloadSucceeded(id):
            guard modelDownload == id else { return [] }
            modelDownload = nil
            localVoiceModel = .ready
            return [.stopDownloadProgress]
        case let .downloadFailed(id, failure):
            guard modelDownload == id else { return [] }
            modelDownload = nil
            // A ready signal during the download wins. The failure must not clobber it.
            if case .downloading = localVoiceModel {
                localVoiceModel = .failed(failure)
            }
            return [.stopDownloadProgress]
        case .voiceModelBecameReady:
            localVoiceModel = .ready
            return []
        case let .startWatchingVoiceModel(interval):
            guard !isWatchingVoiceModel else { return [] }
            isWatchingVoiceModel = true
            return [.watchVoiceModel(interval)]
        case .stopWatchingVoiceModel:
            guard isWatchingVoiceModel else { return [] }
            isWatchingVoiceModel = false
            return [.stopWatchingVoiceModel]
        }
    }
}
