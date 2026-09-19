import AppKit
import SendpointDomain
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case capture
    case preview
    case stacks
    case templates
    case pasting
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Capture"
        case .preview: "Preview"
        case .stacks: "Stacks"
        case .templates: "Templates"
        case .pasting: "Pasting"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .capture: "waveform"
        case .preview: "captions.bubble"
        case .stacks: "rectangle.stack"
        case .templates: "doc.text"
        case .pasting: "clipboard"
        case .system: "gearshape"
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    @Bindable var templateEditor: TemplateEditorState
    @Bindable var permissionState: PermissionState
    let storeHandle: SettingsStoreHandle
    let onSelectTemplate: (UUID) -> Void
    let hotKeyRegistrar: HotKeyRegistrar
    let captureController: CaptureController
    let onSettingsChanged: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowStack: () -> Void

    @State private var tab: SettingsTab = .capture

    static let size = CGSize(width: 920, height: 600)
    private static let sidebarWidth: CGFloat = 200

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        hotKeyRegistrar: HotKeyRegistrar,
        captureController: CaptureController,
        templateEditor: TemplateEditorState,
        permissionState: PermissionState,
        storeHandle: SettingsStoreHandle,
        onSelectTemplate: @escaping (UUID) -> Void,
        onSettingsChanged: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onShowStack: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _shortcuts = Bindable(wrappedValue: shortcuts)
        _voiceSettings = Bindable(wrappedValue: voiceSettings)
        _templateEditor = Bindable(wrappedValue: templateEditor)
        _permissionState = Bindable(wrappedValue: permissionState)
        self.storeHandle = storeHandle
        self.onSelectTemplate = onSelectTemplate
        self.hotKeyRegistrar = hotKeyRegistrar
        self.captureController = captureController
        self.onSettingsChanged = onSettingsChanged
        self.onCheckForUpdates = onCheckForUpdates
        self.onShowStack = onShowStack
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $tab, permissionState: permissionState,
                storeHandle: storeHandle, onShowStack: onShowStack
            )
                .frame(width: Self.sidebarWidth)
            Hairline(axis: .vertical)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
        }
        .frame(
            minWidth: Self.size.width, maxWidth: .infinity,
            minHeight: Self.size.height, maxHeight: .infinity
        )
        .background(Backdrop())
        .font(.uiBody)
        .ignoresSafeArea()
        .tint(Color.primary.opacity(0.85))
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .capture:
            SettingsCapturePane(
                shortcuts: shortcuts,
                voiceSettings: voiceSettings,
                hotKeyRegistrar: hotKeyRegistrar,
                captureController: captureController,
                onSettingsChanged: onSettingsChanged
            )
        case .preview:
            SettingsPreviewPane(
                voiceSettings: voiceSettings,
                captureController: captureController
            )
        case .stacks:
            SettingsStacksPane(
                shortcuts: shortcuts,
                storeHandle: storeHandle,
                hotKeyRegistrar: hotKeyRegistrar,
                onSettingsChanged: onSettingsChanged
            )
        case .templates:
            SettingsTemplatesPane(
                settings: settings,
                editor: templateEditor,
                onSelectTemplate: onSelectTemplate
            )
        case .pasting:
            SettingsPastingPane(
                settings: settings,
                shortcuts: shortcuts,
                hotKeyRegistrar: hotKeyRegistrar,
                onSettingsChanged: onSettingsChanged
            )
        case .system:
            SettingsSystemPane(
                settings: settings,
                permissionState: permissionState,
                onSettingsChanged: onSettingsChanged,
                onCheckForUpdates: onCheckForUpdates
            )
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    @Bindable var permissionState: PermissionState
    let storeHandle: SettingsStoreHandle
    let onShowStack: () -> Void
    @Environment(\.colorScheme) private var scheme

    private let topInset: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
            wordmark
                .padding(.leading, 12)
                .padding(.top, 22)
                .padding(.bottom, 22)
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsSidebarItem(tab: tab, isSelected: tab == selection) {
                        selection = tab
                    }
                }
            }
            Spacer(minLength: 16)
            SettingsStatusCard(
                permissionState: permissionState, storeHandle: storeHandle, onShowStack: onShowStack
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.well(scheme).opacity(0.85))
    }

    private var wordmark: some View {
        HStack(alignment: .center, spacing: 7) {
            Text("Sendpoint")
                .font(.ui(17, weight: .semibold))
                .tracking(-0.2)
            Circle()
                .fill(Ink.accent(scheme))
                .frame(width: 6, height: 6)
                .offset(y: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct SettingsSidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Text(tab.title)
                    .font(.ui(14, weight: .medium))
                    .foregroundStyle(isSelected || hovering ? Color.primary : Color.primary.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Ink.raised(scheme) : (hovering ? Ink.hover : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Ink.hairline.opacity(isSelected ? 1 : 0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isSelected && scheme == .light ? 0.05 : 0), radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SettingsStatusCard: View {
    @Bindable var permissionState: PermissionState
    let storeHandle: SettingsStoreHandle
    let onShowStack: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var stage: SetupHeroStage {
        SetupHeroStage.from(
            accessibility: permissionState.accessibility,
            microphone: permissionState.microphone,
            model: permissionState.localVoiceModel
        )
    }

    private var isActionable: Bool {
        stage == .ready ? storeHandle.store != nil : stage.isActionable
    }

    private var showsStack: Bool { stage == .ready && storeHandle.store != nil }

    private var copy: (kicker: String, title: String, detail: String) {
        switch stage {
        case .ready:
            if let store = storeHandle.store, let current = StackUIFacts(store: store).current {
                ("Current stack", current.name, stackStatusDetail(
                    noteCount: current.noteCount, latest: store.currentNotes.map(\.createdAt).max()
                ))
            } else {
                ("Sendpoint", "Ready to capture", "Runs on this Mac")
            }
        case .accessibility: ("Setup", "Needs Accessibility", "Click to grant")
        case .microphone: ("Setup", "Needs the microphone", "Click to allow")
        case .microphoneSettings: ("Setup", "Microphone is off", "Click to open System Settings")
        case .voiceModel: ("Setup", "Voice model", "Click to download")
        case let .downloading(progress):
            ("Setup", "Downloading voice model", progress.map { "\(Int($0 * 100))%" } ?? "Starting…")
        case .failedOffline: ("Setup", "No internet", "Click to retry")
        case .failedOther: ("Setup", "Download failed", "Click to retry")
        }
    }

    private var accessibilityLabel: String {
        showsStack
            ? "Current stack \(copy.title). \(copy.detail). Opens the stack"
            : "\(copy.title). \(copy.detail)"
    }

    var body: some View {
        Button {
            guard isActionable else { return }
            if stage == .ready { onShowStack() } else { stage.perform(on: permissionState) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stage == .ready ? Ink.accent(scheme) : Ink.amber(scheme))
                        .frame(width: 5, height: 5)
                    Text(copy.kicker)
                        .font(.mono(9.5, weight: .medium))
                        .tracking(1.3)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if isActionable {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .opacity(hovering ? 1 : 0)
                    }
                }
                Spacer(minLength: 8)
                Text(copy.title)
                    .font(.ui(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.detail)
                    .font(.mono(10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 5)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 124)
            .background(Aurora())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(hovering && isActionable ? 1.01 : 1)
            .animation(.snappy(duration: 0.2), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActionable ? .isButton : [])
    }
}

// MARK: - Template dialogs

enum TemplateDialogs {
    static func resolvePendingSelection(_ editor: TemplateEditorState) -> Bool {
        guard editor.pendingTemplateID != nil else { return true }
        guard let decision = dirtyDecision(for: editor) else {
            editor.cancelPendingSelection()
            return false
        }
        return resolve(decision, editor: editor, closesWindow: false)
    }

    static func shouldClose(_ editor: TemplateEditorState) -> Bool {
        guard editor.isDirty else { return true }
        guard let decision = dirtyDecision(for: editor) else { return false }
        return resolve(decision, editor: editor, closesWindow: true)
    }

    static func delete(_ editor: TemplateEditorState) {
        guard let stored = editor.storedTemplate else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(stored.name)”?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try editor.delete()
        } catch {
            showError(error)
        }
    }

    static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Couldn't Change Template"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func dirtyDecision(
        for editor: TemplateEditorState
    ) -> TemplateEditorState.DirtyDecision? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to “\(editor.draft.name)”?"
        alert.informativeText = "Choose what to do with this template."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Save as New…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            guard let name = requestNewName(for: editor) else { return nil }
            return .saveAsNew(name: name)
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private static func resolve(
        _ decision: TemplateEditorState.DirtyDecision,
        editor: TemplateEditorState,
        closesWindow: Bool
    ) -> Bool {
        do {
            if closesWindow {
                return try editor.resolveClose(decision)
            }
            return try editor.resolvePendingSelection(decision)
        } catch {
            showError(error)
            if !closesWindow { editor.cancelPendingSelection() }
            return false
        }
    }

    private static func requestNewName(for editor: TemplateEditorState) -> String? {
        var proposedName = "\(editor.draft.name) Copy"
        while true {
            let alert = NSAlert()
            alert.messageText = "New Template"
            alert.informativeText = "Enter a unique template name."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let field = NSTextField(string: proposedName)
            field.placeholderString = "Template name"
            field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            proposedName = field.stringValue
            do {
                return try editor.validatedNewTemplateName(proposedName)
            } catch {
                showError(error)
            }
        }
    }
}
