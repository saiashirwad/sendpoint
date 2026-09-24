import AppKit
import SendpointDomain
import SwiftUI

enum SetupHeroStage: Equatable {
    case accessibility
    case microphone
    case microphoneSettings
    case voiceModel
    case downloading(progress: Double?)
    case failedOffline
    case failedOther
    case ready

    init(_ stage: PermissionSetupStage) {
        switch stage {
        case .accessibility: self = .accessibility
        case .microphone: self = .microphone
        case .microphoneSettings: self = .microphoneSettings
        case .voiceModel: self = .voiceModel
        case let .downloading(progress): self = .downloading(progress: progress)
        case .failedOffline: self = .failedOffline
        case .failedOther: self = .failedOther
        case .ready: self = .ready
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

    var step: Int {
        switch self {
        case .accessibility: 0
        case .microphone, .microphoneSettings: 1
        case .voiceModel, .downloading, .failedOffline, .failedOther: 2
        case .ready: 3
        }
    }

    var headline: String {
        switch self {
        case .accessibility: "Let Sendpoint read your selection"
        case .microphone: "Let Sendpoint hear you"
        case .microphoneSettings: "The microphone is switched off"
        case .voiceModel: "One download, then it stays here"
        case .downloading: "Fetching the voice model"
        case .failedOffline: "No internet right now"
        case .failedOther: "That download didn't finish"
        case .ready: ""
        }
    }

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

    func perform(on state: PermissionController) {
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
    @Bindable var permissionState: PermissionController
    @Bindable var tour: SetupTour
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    let onComplete: () -> Void
    let onDismiss: () -> Void
    @State private var didFinish = false
    @State private var windowIsVisible = false
    @Environment(\.colorScheme) private var colorScheme

    static let size = NSSize(width: 500, height: 352)
    private static let inset: CGFloat = 32

    init(
        settings: AppSettings,
        permissionState: PermissionController,
        tour: SetupTour,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _permissionState = Bindable(wrappedValue: permissionState)
        _tour = Bindable(wrappedValue: tour)
        _shortcuts = Bindable(wrappedValue: shortcuts)
        _voiceSettings = Bindable(wrappedValue: voiceSettings)
        self.onComplete = onComplete
        self.onDismiss = onDismiss
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
                    .modifier(SetupCard())
            } else if inTour, let tip = tour.step.tip(keys: SetupTourKeys(shortcuts: shortcuts)) {
                Text(tip)
                    .font(.ui(SetupPassage.fontSize))
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: SetupPassage.height, alignment: .topLeading)
                    .modifier(SetupCard())
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
    }

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
        .accessibilityElement(children: .combine)
        .id(headline)
        .onChange(of: headline) { announcePolitely("\(headline). \(detail)") }
        .transition(.blurReplace)
        .animation(.snappy(duration: 0.35), value: headline)
    }

    @ViewBuilder
    private var control: some View {
        if inTour {
            tourControl
        } else if case let .downloading(progress) = stage {
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

    @ViewBuilder
    private var tourControl: some View {
        switch tour.step {
        case .voice, .text:
            QuietButton("Skip") { tour.send(.skip) }
                .frame(height: 28)
        case .send:
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

    private var stage: SetupHeroStage { permissionState.setupStage }
}

private struct SetupHeroPill: View {
    @Bindable var permissionState: PermissionController
    let animates: Bool
    @State private var appeared = false
    @State private var hovering = false

    private var stage: SetupHeroStage { permissionState.setupStage }

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

struct SetupCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
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
}

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
