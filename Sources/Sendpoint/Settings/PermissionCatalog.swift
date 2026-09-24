import SwiftUI

struct PermissionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: CapabilityStatus
    let actionTitle: String?
    let run: () -> Void
}

enum PermissionCatalog {
    static func items(state: PermissionState) -> [PermissionItem] {
        [
            PermissionItem(
                id: "accessibility",
                title: "Accessibility",
                detail: "Reads the selected text",
                status: accessibilityStatus(state),
                actionTitle: accessibilityActionTitle(state),
                run: { performAccessibilityAction(state) }
            ),
            PermissionItem(
                id: "microphone",
                title: "Microphone",
                detail: "For voice notes",
                status: microphoneStatus(state),
                actionTitle: microphoneActionTitle(state),
                run: { performMicrophoneAction(state) }
            ),
            PermissionItem(
                id: "voice-model",
                title: "Voice model",
                detail: "Transcribes on this Mac",
                status: voiceModelStatus(state),
                actionTitle: voiceModelActionTitle(state),
                run: { performVoiceModelAction(state) }
            ),
        ]
    }

    private static func accessibilityStatus(_ state: PermissionState) -> CapabilityStatus {
        switch state.accessibility {
        case .notGranted: .attention("Required")
        case .granted: .ready("Granted")
        }
    }

    private static func microphoneStatus(_ state: PermissionState) -> CapabilityStatus {
        switch state.microphone {
        case .notDetermined: .neutral("Not enabled")
        case .denied: .attention("Denied")
        case .restricted: .attention("Restricted")
        case .granted: .ready("Granted")
        }
    }

    private static func voiceModelStatus(_ state: PermissionState) -> CapabilityStatus {
        switch state.localVoiceModel {
        case .notDownloaded: .neutral("Not downloaded")
        case let .downloading(progress):
            .working(
                label: progress.map { "\(Int($0 * 100))%" } ?? "Downloading…",
                fraction: progress
            )
        case .ready: .ready("Downloaded")
        case .failed(.offline): .attention("No internet connection")
        case .failed(.other): .attention("Download failed")
        }
    }

    private static func accessibilityActionTitle(_ state: PermissionState) -> String? {
        switch state.accessibilityAction {
        case .requestAccessibility: "Grant"
        default: nil
        }
    }

    private static func microphoneActionTitle(_ state: PermissionState) -> String? {
        switch state.microphoneAction {
        case .requestMicrophone: "Allow"
        case .openMicrophoneSettings: "Settings"
        default: nil
        }
    }

    private static func voiceModelActionTitle(_ state: PermissionState) -> String? {
        guard state.localVoiceModelAction == .downloadVoiceModel else { return nil }
        if case .failed = state.localVoiceModel { return "Retry" }
        return "Download"
    }

    private static func performAccessibilityAction(_ state: PermissionState) {
        guard state.accessibilityAction == .requestAccessibility else { return }
        state.requestAccessibility()
    }

    private static func performMicrophoneAction(_ state: PermissionState) {
        switch state.microphoneAction {
        case .requestMicrophone:
            state.requestMicrophone()
        case .openMicrophoneSettings:
            state.openMicrophoneSettings()
        default:
            break
        }
    }

    private static func performVoiceModelAction(_ state: PermissionState) {
        guard state.localVoiceModelAction == .downloadVoiceModel else { return }
        state.downloadModel()
    }
}

enum CapabilityStatus {
    case neutral(String)
    case attention(String)
    case ready(String)
    case working(label: String, fraction: Double?)

    var title: String {
        switch self {
        case let .neutral(title), let .attention(title), let .ready(title):
            title
        case let .working(label, _):
            label
        }
    }
}

struct CapabilityAccessory: View {
    let status: CapabilityStatus
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        if case let .working(label, fraction) = status {
            HStack(spacing: 8) {
                Text(label)
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                CapabilityProgress(fraction: fraction)
                    .frame(width: 56)
            }
        } else if let actionTitle {
            PillButton(actionTitle, action: action)
        } else if case .ready = status {
            ReadyMark()
        } else {
            Text(status.title)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReadyMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private enum Metrics {
        static let size: CGFloat = 16
        static let check: CGFloat = 8
        static let fromScale: CGFloat = 0.58
        static let spring = Animation.spring(duration: 0.36, bounce: 0.30)
    }

    var body: some View {
        ZStack {
            Circle().fill(ink)
            Image(systemName: "checkmark")
                .font(.system(size: Metrics.check, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: 0.4)
        }
        .frame(width: Metrics.size, height: Metrics.size)
        .scaleEffect(appeared ? 1 : Metrics.fromScale)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Metrics.spring) { appeared = true }
        }
        .accessibilityHidden(true)
    }

    private var ink: Color {
        Ink.green(colorScheme)
    }
}

struct CapabilityProgress: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                        .animation(.linear(duration: 0.2), value: fraction)
                }
            }
            .frame(height: 4)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }
}
