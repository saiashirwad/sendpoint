import AppKit
import SwiftUI

/// Looping demo of the recording capsule: two spoken phrases, then a rest.
enum SetupHeroMotion {
    static let period: TimeInterval = 6
    static let speakingDuration: TimeInterval = 4
    /// How long the living pill plays before setup dismisses itself.
    static let completionPause: Duration = .milliseconds(1400)

    static func phase(at time: TimeInterval) -> (mode: VoiceOrb.Mode, level: Double) {
        let cycle = time.truncatingRemainder(dividingBy: period)
        if cycle < speakingDuration {
            return (.live, speechLevel(cycle))
        }
        return (.idle, 0)
    }

    /// Two envelopes inside the speaking window, with a little flutter so
    /// the orb does not swell as a perfect sine.
    static func speechLevel(_ cycle: TimeInterval) -> Double {
        let phrase = cycle < 2 ? cycle / 2 : (cycle - 2) / 2
        let envelope = sin(phrase * .pi)
        let flutter = 0.5 + 0.5 * sin(cycle * 11)
        return min(max(envelope * flutter, 0), 1)
    }
}

/// The next thing the setup pill should do. One stage at a time, in the
/// order Sendpoint actually needs them.
enum SetupHeroStage: Equatable {
    case accessibility
    case microphone
    case microphoneSettings
    case voiceModel
    case downloading(progress: Double?)
    case failedOffline
    case failedOther
    case ready

    static func from(
        accessibility: AccessibilityPermissionState,
        microphone: MicrophonePermissionState,
        model: LocalVoiceModelState
    ) -> SetupHeroStage {
        if accessibility != .granted { return .accessibility }
        switch microphone {
        case .notDetermined: return .microphone
        case .denied, .restricted: return .microphoneSettings
        case .granted: break
        }
        switch model {
        case .notDownloaded: return .voiceModel
        case let .downloading(progress): return .downloading(progress: progress)
        case .failed(.offline): return .failedOffline
        case .failed(.other): return .failedOther
        case .ready: return .ready
        }
    }

    var label: String {
        switch self {
        case .accessibility: "Accessibility"
        case .microphone, .microphoneSettings: "Microphone"
        case .voiceModel, .downloading, .failedOffline, .failedOther: "Voice model"
        case .ready: "Listening"
        }
    }

    var accessory: String? {
        switch self {
        case let .downloading(progress):
            progress.map { "\(Int($0 * 100))%" }
        case .failedOffline: "No internet"
        case .failedOther: "Retry"
        default: nil
        }
    }

    var showsDownloadGlyph: Bool { self == .voiceModel }

    var title: String {
        if showsDownloadGlyph { return "Download voice model" }
        if let accessory { return "\(label), \(accessory)" }
        return label
    }

    var isActionable: Bool {
        switch self {
        case .ready, .downloading: false
        default: true
        }
    }

    /// Coarse setup step. Progress within a step (download percent) must not
    /// count as advancing, or we would steal focus on every poll.
    var step: Int {
        switch self {
        case .accessibility: 0
        case .microphone, .microphoneSettings: 1
        case .voiceModel, .downloading, .failedOffline, .failedOther: 2
        case .ready: 3
        }
    }

    func perform(on state: PermissionState) {
        switch self {
        case .accessibility:
            state.requestAccessibility()
        case .microphone:
            state.requestMicrophone()
        case .microphoneSettings:
            state.openMicrophoneSettings()
        case .voiceModel, .failedOffline, .failedOther:
            state.downloadModel()
        case .downloading, .ready:
            break
        }
    }
}

struct SetupView: View {
    @Bindable var settings: AppSettings
    @Bindable var permissionState: PermissionState
    let onComplete: () -> Void
    let onDismiss: () -> Void
    @State private var didFinish = false
    @Environment(\.colorScheme) private var colorScheme

    /// Hero pill, progress dots, footer. Never scrolls. No title bar.
    static let size = NSSize(width: 480, height: 320)

    init(
        settings: AppSettings,
        permissionState: PermissionState,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _permissionState = Bindable(wrappedValue: permissionState)
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                SetupHeroPill(permissionState: permissionState)
                SetupProgressDots(
                    accessibility: permissionState.accessibility == .granted,
                    microphone: permissionState.microphone == .granted,
                    model: permissionState.localVoiceModel == .ready
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PaletteTint.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        }
        .ignoresSafeArea()
        .onExitCommand {
            guard stage == .ready else { return }
            onDismiss()
        }
        .task { await permissionState.watchVoiceModel() }
        .task(id: stage) {
            guard stage == .ready else { return }
            do {
                try await Task.sleep(for: SetupHeroMotion.completionPause)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        settings.completeSetup()
        onComplete()
    }

    private var stage: SetupHeroStage {
        SetupHeroStage.from(
            accessibility: permissionState.accessibility,
            microphone: permissionState.microphone,
            model: permissionState.localVoiceModel
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            SettingsFooterButton("Continue", keys: "↩") {
                finish()
            }
            .keyboardShortcut(.defaultAction)
            .opacity(stage == .ready ? 1 : 0)
            .disabled(stage != .ready)
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
    static func items(state: PermissionState) -> [PermissionItem] {
        [
            PermissionItem(
                id: "accessibility",
                title: "Accessibility",
                detail: "Reads the selected text when you take a typed note.",
                status: accessibilityStatus(state),
                actionTitle: accessibilityActionTitle(state),
                run: { performAccessibilityAction(state) }
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

struct PermissionCapabilityList: View {
    @Bindable var permissionState: PermissionState

    init(permissionState: PermissionState) {
        _permissionState = Bindable(wrappedValue: permissionState)
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
        PermissionCatalog.items(state: permissionState)
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
        Group {
            if actionTitle != nil {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
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

/// The recording capsule, alive, the way AirPods pairing shows the case.
/// Until everything is granted it is also the only control: click it to
/// do the next thing Sendpoint needs.
private struct SetupHeroPill: View {
    @Bindable var permissionState: PermissionState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var hovering = false

    private var stage: SetupHeroStage {
        SetupHeroStage.from(
            accessibility: permissionState.accessibility,
            microphone: permissionState.microphone,
            model: permissionState.localVoiceModel
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !usesDemoMotion)) { context in
            let demo = SetupHeroMotion.phase(
                at: context.date.timeIntervalSinceReferenceDate
            )
            pill(
                mode: orbMode(demo: demo),
                level: usesDemoMotion && !reduceMotion ? demo.level : 0
            )
        }
        .scaleEffect((appeared ? 1 : 0.92) * (hovering && stage.isActionable ? 1.04 : 1))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                appeared = true
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.title)
        .accessibilityAddTraits(stage.isActionable ? .isButton : [])
    }

    private var usesDemoMotion: Bool { stage == .ready }

    private func orbMode(demo: (mode: VoiceOrb.Mode, level: Double)) -> VoiceOrb.Mode {
        if reduceMotion { return .idle }
        switch stage {
        case .ready: return demo.mode
        case .downloading: return .thinking
        case .failedOffline, .failedOther: return .flat
        default: return .idle
        }
    }

    private func activate() {
        guard stage.isActionable else { return }
        stage.perform(on: permissionState)
    }

    private func pill(mode: VoiceOrb.Mode, level: Double) -> some View {
        let palette = OverlayPalette.against(colorScheme)
        return HStack(spacing: 10) {
            Text(stage.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.ink.opacity(0.9))
                .contentTransition(.opacity)
            if let accessory = stage.accessory {
                Text(accessory)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.ink.opacity(0.55))
                    .contentTransition(.opacity)
            }
            if stage.showsDownloadGlyph {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink.opacity(0.9))
                    .frame(width: 22, height: 22)
            } else {
                VoiceOrb(mode: mode, level: level, ink: palette.ink, amber: palette.amber)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: VoiceCaptureLayout.pillHeight)
        .background(Capsule().fill(palette.paper))
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [palette.ink.opacity(0.14), palette.ink.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .environment(\.colorScheme, palette.contentScheme)
        .scaleEffect(1.12)
        .contentShape(Capsule())
        .animation(.snappy(duration: 0.22), value: stage.label)
        .animation(.snappy(duration: 0.22), value: stage.accessory)
    }
}

private struct SetupProgressDots: View {
    let accessibility: Bool
    let microphone: Bool
    let model: Bool

    var body: some View {
        HStack(spacing: 7) {
            dot(accessibility)
            dot(microphone)
            dot(model)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(filled) of 3 ready")
    }

    private var filled: Int {
        [accessibility, microphone, model].filter(\.self).count
    }

    private func dot(_ on: Bool) -> some View {
        Circle()
            .fill(Color.primary.opacity(on ? 0.85 : 0.14))
            .frame(width: 5, height: 5)
            .animation(.snappy(duration: 0.28), value: on)
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

/// Borderless so setup matches the recording pill, not a document window.
/// Esc dismisses; there is no close button.
final class SetupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SetupWindowController: NSObject, NSWindowDelegate {
    private enum Lifecycle {
        case active
        case tornDown
    }

    private let window: NSPanel
    private let permissionState: PermissionState
    private let surfaces: SurfaceCoordinator
    private var lifecycle: Lifecycle = .active
    private var pollingTask: Task<Void, Never>?
    private var lastStep: Int?

    init(
        settings: AppSettings,
        permissionState: PermissionState,
        surfaces: SurfaceCoordinator,
        onComplete: @escaping () -> Void
    ) {
        let window = Self.makeWindow()
        self.permissionState = permissionState
        self.surfaces = surfaces
        self.window = window
        super.init()
        let hosting = NSHostingView(rootView: SetupView(
            settings: settings,
            permissionState: permissionState,
            onComplete: onComplete,
            onDismiss: { [weak self] in self?.window.close() }
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

    static func makeWindow() -> NSPanel {
        let window = SetupPanel(
            contentRect: NSRect(origin: .zero, size: SetupView.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Sendpoint"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        return window
    }

    func show() {
        guard lifecycle == .active else { return }
        surfaces.present(.setup)
    }

    private func present() {
        startPolling()
        if !window.isVisible {
            window.center()
        }
        window.presentActivated()
    }

    private var currentStage: SetupHeroStage {
        SetupHeroStage.from(
            accessibility: permissionState.accessibility,
            microphone: permissionState.microphone,
            model: permissionState.localVoiceModel
        )
    }

    private func revealAfterStepChange() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() {
        stopPolling()
        window.orderOut(nil)
        window.close()
    }

    func teardown() {
        guard lifecycle == .active else { return }
        surfaces.unregister(.setup)
        lifecycle = .tornDown
        stopPolling()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    private func startPolling() {
        stopPolling()
        lastStep = currentStage.step
        let permissionState = permissionState
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.lifecycle == .active else { return }
                permissionState.refresh()
                let step = self.currentStage.step
                if self.lastStep != step {
                    self.lastStep = step
                    self.revealAfterStepChange()
                }
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
        surfaces.userClosed(.setup)
    }
}

