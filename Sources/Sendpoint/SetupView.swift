import AppKit
import SwiftUI

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

    static let stepNames = ["Accessibility", "Microphone", "Voice model"]

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

    /// The ask, in plain words. One line at 22pt in the setup window.
    var headline: String {
        switch self {
        case .accessibility: "Let Sendpoint read your selection"
        case .microphone: "Let Sendpoint hear you"
        case .microphoneSettings: "The microphone is switched off"
        case .voiceModel: "One download, then it stays here"
        case .downloading: "Fetching the voice model"
        case .failedOffline: "No internet right now"
        case .failedOther: "That download didn't finish"
        // Once everything is granted the tour speaks; see SetupTour.
        case .ready: ""
        }
    }

    /// Why, or what happens next. One sentence, one line.
    var detail: String {
        switch self {
        case .accessibility:
            "Asked once. A typed note quotes the passage you selected."
        case .microphone:
            "Hold a key to speak. Nothing is heard until you do."
        case .microphoneSettings:
            "Turn Sendpoint on under Privacy & Security, Microphone."
        case .voiceModel:
            "Transcribed on this Mac. Audio never leaves it."
        case .downloading:
            "About a minute on a good connection."
        case .failedOffline:
            "Reconnect, then try again."
        case .failedOther:
            "Try once more. Nothing else needs to change."
        case .ready:
            ""
        }
    }

    /// The button. Nil while a download runs; progress stands in for it.
    var actionTitle: String? {
        switch self {
        case .accessibility: "Grant access"
        case .microphone: "Allow"
        case .microphoneSettings: "Open Settings"
        case .voiceModel: "Download"
        case .downloading: nil
        case .failedOffline, .failedOther: "Try again"
        case .ready: nil
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
    @Bindable var tour: SetupTour
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onOpenStack: () -> Void
    @State private var didFinish = false
    @State private var windowIsVisible = false
    @Environment(\.colorScheme) private var colorScheme

    /// Emblem, one ask, the step rail and its button. Never scrolls.
    static let size = NSSize(width: 500, height: 352)
    private static let inset: CGFloat = 32

    init(
        settings: AppSettings,
        permissionState: PermissionState,
        tour: SetupTour,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onOpenStack: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _permissionState = Bindable(wrappedValue: permissionState)
        _tour = Bindable(wrappedValue: tour)
        _shortcuts = Bindable(wrappedValue: shortcuts)
        _voiceSettings = Bindable(wrappedValue: voiceSettings)
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self.onOpenStack = onOpenStack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeroPill(permissionState: permissionState, animates: windowIsVisible)
                .padding(.top, 30)
            Spacer(minLength: 0)
            steps
            ask
                .padding(.top, 12)
            if inTour, let passage = tour.step.passage {
                SetupPassage(text: passage)
                    .id(tour.step)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Ink.raised(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Ink.rim(colorScheme), lineWidth: 1)
                    )
                    .padding(.top, 16)
            }
            control
                .padding(.top, inTour ? 20 : 24)
        }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset - 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Aurora(strength: 0.55))
        .background(WindowVisibilityReporter(isVisible: $windowIsVisible))
        .font(.uiBody)
        .clipShape(RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous)
                .strokeBorder(Ink.rim(colorScheme), lineWidth: 1)
        }
        .ignoresSafeArea()
        .onExitCommand {
            guard stage == .ready else { return }
            onDismiss()
        }
        .task(id: windowIsVisible) {
            guard windowIsVisible else { return }
            await permissionState.watchVoiceModel()
        }
    }

    /// Permissions first; once they are in, the tour takes the same rail.
    private var inTour: Bool { stage == .ready }

    private var steps: some View {
        Group {
            if inTour {
                SetupSteps(names: SetupTour.Step.railNames, step: tour.step.rawValue)
            } else {
                SetupSteps(names: SetupHeroStage.stepNames, step: stage.step)
            }
        }
        .animation(.snappy(duration: 0.3), value: inTour)
    }

    private var headline: String {
        inTour ? tour.step.headline : stage.headline
    }

    private var detail: String {
        inTour
            ? tour.step.detail(keys: SetupTourKeys(shortcuts: shortcuts), voiceMode: voiceSettings.voiceMode)
            : stage.detail
    }

    /// Headline and one line of why. Swaps as a block when the stage moves
    /// on, so each step reads as a new page rather than edited text.
    private var ask: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.ui(22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(detail)
                .font(.ui(13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(headline)
        .transition(.blurReplace)
        .animation(.snappy(duration: 0.35), value: headline)
    }

    @ViewBuilder
    private var control: some View {
        if inTour {
            tourControl
        } else if case let .downloading(progress) = stage {
            // The number is the whole status: it climbs from the first byte
            // through the CoreML compile and lands on 100 as the stage flips.
            Text(progress.map { "\(Int($0 * 100))%" } ?? "Starting")
                .font(.mono(13, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: progress)
                .frame(height: 30)
        } else if let title = stage.actionTitle {
            InkButton(title, keys: "↩") { activate() }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// A skip while a note is awaited; the stack opens for real with setup
    /// still behind it; Done is the only way setup completes.
    @ViewBuilder
    private var tourControl: some View {
        switch tour.step {
        case .voice, .text:
            QuietButton("Skip") { tour.send(.skip) }
                .frame(height: 28)
        case .stack:
            InkButton("Open stack", keys: "↩") { onOpenStack(); tour.send(.openedStack) }
                .keyboardShortcut(.defaultAction)
        case .done:
            InkButton("Done", keys: "↩") { finish() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func activate() {
        stage.perform(on: permissionState)
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
}

/// The recording capsule, alive, wearing the wordmark: the emblem at the
/// top of setup. It lights up once everything is granted, thinks
/// while the model downloads, and goes flat when a download fails.
/// Clicking it does the next thing Sendpoint needs, like the button.
private struct SetupHeroPill: View {
    @Bindable var permissionState: PermissionState
    let animates: Bool
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
        WordmarkPill(mode: orbMode, animates: animates)
        .scaleEffect((appeared ? 1 : 0.9) * (hovering && stage.isActionable ? 1.04 : 1))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.title)
        .accessibilityAddTraits(stage.isActionable ? .isButton : [])
    }

    private var orbMode: VoiceOrb.Mode {
        switch stage {
        case .ready: return .live
        case .downloading: return .thinking
        case .failedOffline, .failedOther: return .flat
        default: return .idle
        }
    }

    private func activate() {
        guard stage.isActionable else { return }
        stage.perform(on: permissionState)
    }
}

/// The steps as the kicker line: done ones ticked, the current one marked
/// with the accent, the rest waiting in grey.
private struct SetupSteps: View {
    let names: [String]
    let step: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 7) {
                    marker(for: index)
                    Text(name)
                        .font(.mono(9.5, weight: .medium))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(index == step ? Color.primary : Color.secondary.opacity(index < step ? 1 : 0.7))
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(min(step, names.count)) of \(names.count) done")
    }

    @ViewBuilder
    private func marker(for index: Int) -> some View {
        if index < step {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: 8, height: 8)
                .transition(.scale.combined(with: .opacity))
        } else if index == step {
            Circle()
                .fill(Ink.accent(colorScheme))
                .frame(width: 6, height: 6)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                .frame(width: 7, height: 7)
                .frame(width: 8, height: 8)
        }
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

/// Status on the trailing edge of a capability row: progress, a verb to
/// click, a ready mark, or a quiet caption.
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

/// Two lines the user can select for real, on their own sheet of paper so
/// they read as a document rather than the window's chrome. A text view
/// rather than SwiftUI text so the capture's Accessibility read finds the
/// selection the same way it does in any other app.
struct SetupPassage: NSViewRepresentable {
    let text: String

    static let fontSize: CGFloat = 14
    static let height: CGFloat = 40

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.font = .ui(Self.fontSize)
        view.textColor = .labelColor
        view.string = text
        view.setAccessibilityLabel("Text to select")
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        guard view.string != text else { return }
        view.string = text
        view.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? SetupView.size.width, height: Self.height)
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
    private let tour = SetupTour()
    /// Every note in every stack, or nil until the store has loaded.
    private let noteCount: () -> Int?
    private var lifecycle: Lifecycle = .active
    private var pollingTask: Task<Void, Never>?
    private var lastStep: Int?

    init(
        settings: AppSettings,
        permissionState: PermissionState,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        surfaces: SurfaceCoordinator,
        noteCount: @escaping () -> Int?,
        onComplete: @escaping () -> Void,
        onOpenStack: @escaping () -> Void
    ) {
        let window = Self.makeWindow()
        self.permissionState = permissionState
        self.surfaces = surfaces
        self.noteCount = noteCount
        self.window = window
        super.init()
        let hosting = NSHostingView(rootView: SetupView(
            settings: settings,
            permissionState: permissionState,
            tour: tour,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            onComplete: onComplete,
            onDismiss: { [weak self] in self?.window.close() },
            onOpenStack: onOpenStack
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
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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

    /// Permission steps, then tour slides. A change means the user acted
    /// somewhere else, so setup comes forward to show the next thing.
    private var currentStep: Int {
        let stage = currentStage
        return stage == .ready ? stage.step + tour.step.rawValue : stage.step
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
        lastStep = currentStep
        let permissionState = permissionState
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.lifecycle == .active else { return }
                permissionState.refresh()
                if let count = self.noteCount() { self.tour.send(.noteCount(count)) }
                let step = self.currentStep
                if self.lastStep != step {
                    self.lastStep = step
                    // The stack palette closes when it loses key status, so
                    // setup must not come forward over it for the last slide.
                    if self.tour.step != .done { self.revealAfterStepChange() }
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
