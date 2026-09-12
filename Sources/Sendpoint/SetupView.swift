import AppKit
import SwiftUI

struct SetupView: View {
    @Bindable var settings: AppSettings
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Paper clearance, three 40pt rows, air, 36pt footer. Never scrolls.
    static let size = NSSize(width: 480, height: 320)

    init(
        settings: AppSettings,
        permissionState: PermissionState,
        onShowAccessibilityHelper: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _permissionState = Bindable(wrappedValue: permissionState)
        self.onShowAccessibilityHelper = onShowAccessibilityHelper
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 52)
            PermissionCapabilityList(
                permissionState: permissionState,
                onShowAccessibilityHelper: onShowAccessibilityHelper
            )
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PaletteTint.surface(colorScheme))
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            SettingsFooterButton("Continue", keys: "↩") {
                settings.completeSetup()
                onComplete()
            }
            .disabled(!permissionState.isVoiceReady)
            .foregroundStyle(permissionState.isVoiceReady ? Color.primary : Color.secondary)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
}

struct PermissionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: CapabilityStatus
    let actionTitle: String?
    let run: () -> Void
}

enum PermissionCatalog {
    static func items(
        state: PermissionState,
        onShowAccessibilityHelper: @escaping () -> Void
    ) -> [PermissionItem] {
        [
            PermissionItem(
                id: "accessibility",
                title: "Accessibility",
                detail: "Reads the selected text when you take a typed note.",
                status: accessibilityStatus(state),
                actionTitle: accessibilityActionTitle(state),
                run: { performAccessibilityAction(state, onShowAccessibilityHelper) }
            ),
            PermissionItem(
                id: "microphone",
                title: "Microphone",
                detail: "Records when you use the voice shortcut.",
                status: microphoneStatus(state),
                actionTitle: microphoneActionTitle(state),
                run: { performMicrophoneAction(state) }
            ),
            PermissionItem(
                id: "voice-model",
                title: "Voice model",
                detail: "Transcribes on this Mac, without sending audio away.",
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
        case .requestAccessibility, .showAccessibilityHelper: "Grant"
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

    private static func performAccessibilityAction(
        _ state: PermissionState,
        _ onShowAccessibilityHelper: @escaping () -> Void
    ) {
        switch state.accessibilityAction {
        case .requestAccessibility:
            state.requestAccessibility()
            onShowAccessibilityHelper()
        case .showAccessibilityHelper:
            onShowAccessibilityHelper()
        default:
            break
        }
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
        VStack(spacing: 0) {
            ForEach(items) { item in
                CapabilityRow(
                    title: item.title,
                    status: item.status,
                    actionTitle: item.actionTitle,
                    action: item.run
                )
            }
        }
        .task {
            await permissionState.watchVoiceModel()
        }
    }

    private var items: [PermissionItem] {
        PermissionCatalog.items(
            state: permissionState,
            onShowAccessibilityHelper: onShowAccessibilityHelper
        )
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

private struct CapabilityRow: View {
    let title: String
    let status: CapabilityStatus
    let actionTitle: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .background(PaletteTint.wash(highlighted: false, hovering: hovering && actionTitle != nil))
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(actionTitle == nil ? [] : .isButton)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14))
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private var trailing: some View {
        CapabilityAccessory(status: status, actionTitle: actionTitle)
    }

    private var accessibilityValue: String {
        actionTitle ?? status.title
    }
}

/// Status on the trailing edge of a capability row: progress, a verb, a
/// ready mark, or a quiet caption.
struct CapabilityAccessory: View {
    let status: CapabilityStatus
    var actionTitle: String? = nil

    var body: some View {
        if case let .working(label, fraction) = status {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                CapabilityProgress(fraction: fraction)
                    .frame(width: 56)
            }
        } else if let actionTitle {
            Text(actionTitle)
                .font(.system(size: 12, weight: .medium))
        } else if case .ready = status {
            ReadyMark()
        } else {
            Text(status.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Paper check on a green disc. Pops in once; stays put after that.
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
        colorScheme == .dark
            ? Color(red: 0.36, green: 0.80, blue: 0.54)
            : Color(red: 0.17, green: 0.63, blue: 0.41)
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
        NSWindow.paperDialog("Set Up Sendpoint", size: SetupView.size)
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

struct AccessibilityHelperView: View {
    @Bindable var permissionState: PermissionState
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    static let size = NSSize(width: 480, height: 240)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 52)
            VStack(spacing: 5) {
                Text("Enable Sendpoint")
                    .font(.title3.weight(.semibold))
                Text("Privacy & Security → Accessibility")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PaletteTint.surface(colorScheme))
        .ignoresSafeArea()
        .onExitCommand(perform: onClose)
        .accessibilityHint(permissionState.accessibility == .granted
            ? "Accessibility granted"
            : "Accessibility is not granted yet")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Closes when granted")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SettingsFooterButton("Open Settings", keys: "↩", action: onOpenSettings)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
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
        let hosting = NSHostingView(rootView: AccessibilityHelperView(
            permissionState: permissionState,
            onOpenSettings: { [weak permissionState] in
                guard let permissionState else { return }
                permissionState.openAccessibilitySettings()
            },
            onClose: { [weak self] in self?.close() }
        ))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(AccessibilityHelperView.size)
        window.center()
        window.delegate = self
        surfaces.register(.accessibilityHelper, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide(closingWindow: false) }
        ))
    }

    static func makeWindow() -> NSWindow {
        NSWindow.paperDialog("Accessibility Setup", size: AccessibilityHelperView.size)
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
