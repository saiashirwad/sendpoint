import AppKit
import SwiftUI

struct SetupView: View {
    @Bindable var settings: AppSettings
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    static let size = NSSize(width: 540, height: 460)

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        permissionState: PermissionState,
        onShowAccessibilityHelper: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _shortcuts = Bindable(wrappedValue: shortcuts)
        _voiceSettings = Bindable(wrappedValue: voiceSettings)
        _permissionState = Bindable(wrappedValue: permissionState)
        self.onShowAccessibilityHelper = onShowAccessibilityHelper
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    SettingsSection("Setup") {
                        PermissionCapabilityList(
                            permissionState: permissionState,
                            onShowAccessibilityHelper: onShowAccessibilityHelper
                        )
                    }
                    SettingsSection("Capture a note") {
                        SettingsRowGroup {
                            HowToRow(
                                icon: "mic",
                                lead: "Use your voice",
                                sentence: voiceSettings.voiceMode.detail,
                                keycap: shortcuts.voiceCaptureCombo.displayString
                            )
                            SettingsDivider()
                            HowToRow(
                                icon: "square.and.pencil",
                                lead: "Type a note",
                                sentence: "Write alongside the selected passage.",
                                keycap: shortcuts.captureCombo.displayString
                            )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.automatic)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.emphasizedKeycaps, true)
        .background(PaletteTint.surface(colorScheme))
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.image(pointSize: 18))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sendpoint")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Your notes stay on this Mac", systemImage: "lock")
                    .font(.system(size: 11, weight: .medium))
                Text(permissionState.isVoiceReady
                     ? "Voice transcription runs locally, too."
                     : "Complete setup above to continue.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                settings.completeSetup()
                onComplete()
            } label: {
                Text("Start using Sendpoint")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(PaletteTint.surface(colorScheme))
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 7))
                .opacity(permissionState.isVoiceReady ? 1 : 0.35)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!permissionState.isVoiceReady)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

}

struct PermissionCapabilityList: View {
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void

    init(
        permissionState: PermissionState,
        onShowAccessibilityHelper: @escaping () -> Void
    ) {
        _permissionState = Bindable(wrappedValue: permissionState)
        self.onShowAccessibilityHelper = onShowAccessibilityHelper
    }

    var body: some View {
        SettingsRowGroup {
            accessibilityRow
            SettingsDivider(pastIcon: false)
            microphoneRow
            SettingsDivider(pastIcon: false)
            voiceModelRow
        }
        .task {
            await permissionState.watchVoiceModel()
        }
    }

    private var accessibilityRow: some View {
        CapabilityRow(
            title: "Accessibility",
            reason: "Reads the text you select.",
            status: accessibilityStatus,
            actionTitle: accessibilityActionTitle,
            showsProgress: false,
            action: performAccessibilityAction
        )
    }

    private var microphoneRow: some View {
        CapabilityRow(
            title: "Microphone",
            reason: "Listens only while a voice note is open.",
            status: microphoneStatus,
            actionTitle: microphoneActionTitle,
            showsProgress: false,
            action: performMicrophoneAction
        )
    }

    private var voiceModelRow: some View {
        CapabilityRow(
            title: "Local voice model",
            reason: voiceModelReason,
            status: voiceModelStatus,
            actionTitle: voiceModelActionTitle,
            showsProgress: voiceModelIsDownloading,
            action: performVoiceModelAction
        )
    }

    private var voiceModelReason: String {
        if case .ready = permissionState.localVoiceModel {
            return "Parakeet v3, speech to text on this Mac."
        }
        return "Parakeet v3, a one-time 460 MB download."
    }

    private var accessibilityStatus: CapabilityStatus {
        switch permissionState.accessibility {
        case .notGranted: .attention("Required")
        case .granted: .ready("Granted")
        }
    }

    private var microphoneStatus: CapabilityStatus {
        switch permissionState.microphone {
        case .notDetermined: .neutral("Not enabled")
        case .denied: .attention("Denied")
        case .restricted: .attention("Restricted")
        case .granted: .ready("Granted")
        }
    }

    private var voiceModelStatus: CapabilityStatus {
        switch permissionState.localVoiceModel {
        case .notDownloaded: .neutral("Not downloaded")
        case let .downloading(progress):
            .neutral(progress.map { "Downloading… \(Int($0 * 100))%" } ?? "Downloading…")
        case .ready: .ready("Downloaded")
        case .failed(.offline): .attention("No internet connection")
        case .failed(.other): .attention("Download failed")
        }
    }

    private var voiceModelIsDownloading: Bool {
        if case .downloading = permissionState.localVoiceModel {
            return true
        }
        return false
    }

    private var accessibilityActionTitle: String? {
        switch permissionState.accessibilityAction {
        case .requestAccessibility: "Grant Access…"
        case .showAccessibilityHelper: "Finish Setup…"
        default: nil
        }
    }

    private var microphoneActionTitle: String? {
        switch permissionState.microphoneAction {
        case .requestMicrophone: "Allow Microphone…"
        case .openMicrophoneSettings: "Open System Settings…"
        default: nil
        }
    }

    private var voiceModelActionTitle: String? {
        guard permissionState.localVoiceModelAction == .downloadVoiceModel else { return nil }
        if case .failed = permissionState.localVoiceModel { return "Retry Download…" }
        return "Download Model…"
    }

    private func performAccessibilityAction() {
        switch permissionState.accessibilityAction {
        case .requestAccessibility:
            permissionState.requestAccessibility()
            onShowAccessibilityHelper()
        case .showAccessibilityHelper:
            onShowAccessibilityHelper()
        default:
            break
        }
    }

    private func performMicrophoneAction() {
        switch permissionState.microphoneAction {
        case .requestMicrophone:
            permissionState.requestMicrophone()
        case .openMicrophoneSettings:
            permissionState.openMicrophoneSettings()
        default:
            break
        }
    }

    private func performVoiceModelAction() {
        guard permissionState.localVoiceModelAction == .downloadVoiceModel else { return }
        permissionState.downloadModel()
    }

}

private enum CapabilityStatus {
    case neutral(String)
    case attention(String)
    case ready(String)

    var title: String {
        switch self {
        case let .neutral(title), let .attention(title), let .ready(title): title
        }
    }

    /// Ready reads quietly once everything is in place; only trouble is loud.
    var textColor: Color {
        switch self {
        case .neutral, .ready: .secondary
        case .attention: .orange
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let reason: String
    let status: CapabilityStatus
    let actionTitle: String?
    let showsProgress: Bool
    let action: () -> Void

    var body: some View {
        SettingsIconRow(title: title, detail: reason) {
            VStack(alignment: .trailing, spacing: 7) {
                statusLabel
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                }
            }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            if case .ready = status {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 12)
            }
            Text(status.title)
                .font(.callout)
                .foregroundStyle(status.textColor)
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
final class SetupWindowController: NSObject, NSWindowDelegate {
    private enum Lifecycle {
        case active
        case tornDown
    }

    private let window: NSWindow
    private let surfaces: SurfaceCoordinator
    private var lifecycle: Lifecycle = .active

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        permissionState: PermissionState,
        surfaces: SurfaceCoordinator,
        onShowAccessibilityHelper: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        let window = Self.makeWindow()
        self.surfaces = surfaces
        self.window = window
        super.init()
        let hosting = NSHostingView(rootView: SetupView(
            settings: settings,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            permissionState: permissionState,
            onShowAccessibilityHelper: onShowAccessibilityHelper,
            onComplete: onComplete
        ))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(SetupView.size)
        window.center()
        window.delegate = self
        surfaces.register(.setup, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide() }
        ))
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SetupView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Set Up Sendpoint"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }

    func show() {
        guard lifecycle == .active else { return }
        surfaces.present(.setup)
    }

    private func present() {
        window.center()
        window.presentActivated()
    }

    private func hide() {
        window.orderOut(nil)
        window.close()
    }

    func teardown() {
        guard lifecycle == .active else { return }
        surfaces.unregister(.setup)
        lifecycle = .tornDown
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        surfaces.userClosed(.setup)
    }
}

private struct AccessibilityHelperView: View {
    @Bindable var permissionState: PermissionState
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sendpoint")
                        .font(.title2.weight(.semibold))
                    Label(
                        permissionState.accessibility == .granted
                            ? "Accessibility granted"
                            : "Accessibility needs a manual grant",
                        systemImage: permissionState.accessibility == .granted
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(permissionState.accessibility == .granted ? Color.primary : .orange)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Finish in System Settings")
                    .font(.headline)
                Text("1. Open Privacy & Security → Accessibility.")
                Text("2. Turn on Sendpoint in the app list.")
                Text("3. Return here. This window closes when access is granted.")
            }

            HStack {
                Button("Close", action: onClose)
                Spacer()
                Button("Open Accessibility Settings…", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 470)
    }
}
final class AccessibilityHelperWindowController: NSObject, NSWindowDelegate {
    private enum Lifecycle {
        case hidden
        case visible
        case tornDown
    }

    private let permissionState: PermissionState
    private let surfaces: SurfaceCoordinator
    private let window: NSWindow
    private var lifecycle: Lifecycle = .hidden
    private var pollingTask: Task<Void, Never>?

    init(permissionState: PermissionState, surfaces: SurfaceCoordinator) {
        self.permissionState = permissionState
        self.surfaces = surfaces
        let window = Self.makeWindow()
        self.window = window
        super.init()
        window.contentView = NSHostingView(rootView: AccessibilityHelperView(
            permissionState: permissionState,
            onOpenSettings: { [weak permissionState] in
                guard let permissionState else { return }
                permissionState.openAccessibilitySettings()
            },
            onClose: { [weak self] in self?.close() }
        ))
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 470, height: 310))
        window.center()
        window.delegate = self
        surfaces.register(.accessibilityHelper, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide(closingWindow: false) }
        ))
    }

    static func makeWindow() -> NSWindow {
        NSWindow.titledDialog("Accessibility Setup", size: NSSize(width: 470, height: 310))
    }

    func show() {
        guard lifecycle != .tornDown else { return }
        surfaces.present(.accessibilityHelper)
    }

    private func present() {
        lifecycle = .visible
        permissionState.refreshAccessibility()
        startPolling()
        window.center()
        window.presentActivated()
    }

    func close() {
        surfaces.dismiss(.accessibilityHelper)
    }

    func teardown() {
        guard lifecycle != .tornDown else { return }
        surfaces.unregister(.accessibilityHelper)
        lifecycle = .tornDown
        pollingTask?.cancel()
        pollingTask = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        surfaces.userClosed(.accessibilityHelper)
        hide(closingWindow: true)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while let self, self.lifecycle == .visible {
                guard !Task.isCancelled else { return }
                self.permissionState.refreshAccessibility()
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch {
                    return
                }
                guard !Task.isCancelled, self.lifecycle == .visible else { return }
                if self.permissionState.accessibility == .granted {
                    self.surfaces.dismiss(.accessibilityHelper)
                    return
                }
            }
        }
    }

    private func hide(closingWindow: Bool) {
        guard lifecycle == .visible else { return }
        lifecycle = .hidden
        pollingTask?.cancel()
        pollingTask = nil
        guard !closingWindow else { return }
        window.orderOut(nil)
        window.close()
    }
}
