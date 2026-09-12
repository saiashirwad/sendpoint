import AppKit
import SendpointDomain
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case capture
    case shortcuts
    case templates
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: "Shortcuts"
        case .templates: "Templates"
        case .capture: "General"
        case .permissions: "Permissions"
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    @Bindable var templateEditor: TemplateEditorState
    @Bindable var permissionState: PermissionState
    let onSelectTemplate: (UUID) -> Void
    let onShowAccessibilityHelper: () -> Void
    let hotKeyRegistrar: HotKeyRegistrar
    let captureController: CaptureController
    let onSettingsChanged: () -> Void

    @State private var tab: SettingsTab = .capture
    @Environment(\.colorScheme) private var colorScheme

    /// The smallest the window goes; it can be dragged larger.
    static let size = CGSize(width: 780, height: 620)
    private static let sidebarWidth: CGFloat = 220
    private static let titleBarHeight: CGFloat = 52
    /// Cards stop stretching past this so a wide window stays readable.
    private static let contentMaxWidth: CGFloat = 760

    init(
        settings: AppSettings,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        hotKeyRegistrar: HotKeyRegistrar,
        captureController: CaptureController,
        templateEditor: TemplateEditorState,
        permissionState: PermissionState,
        onSelectTemplate: @escaping (UUID) -> Void,
        onShowAccessibilityHelper: @escaping () -> Void,
        onSettingsChanged: @escaping () -> Void
    ) {
        _settings = Bindable(wrappedValue: settings)
        _shortcuts = Bindable(wrappedValue: shortcuts)
        _voiceSettings = Bindable(wrappedValue: voiceSettings)
        _templateEditor = Bindable(wrappedValue: templateEditor)
        _permissionState = Bindable(wrappedValue: permissionState)
        self.onSelectTemplate = onSelectTemplate
        self.onShowAccessibilityHelper = onShowAccessibilityHelper
        self.hotKeyRegistrar = hotKeyRegistrar
        self.captureController = captureController
        self.onSettingsChanged = onSettingsChanged
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $tab, topInset: Self.titleBarHeight)
                .frame(width: Self.sidebarWidth)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                        if !shortcuts.shortcutRegistrationIssues.isEmpty {
                            SettingsShortcutIssues(issues: shortcuts.shortcutRegistrationIssues)
                        }
                        switch tab {
                        case .shortcuts:
                            SettingsShortcutsPane(
                                settings: settings,
                                shortcuts: shortcuts,
                                voiceSettings: voiceSettings,
                                hotKeyRegistrar: hotKeyRegistrar,
                                onSettingsChanged: onSettingsChanged
                            )
                        case .templates:
                            SettingsTemplatesPane(
                                settings: settings,
                                editor: templateEditor,
                                onSelectTemplate: onSelectTemplate
                            )
                        case .capture:
                            SettingsGeneralPane(
                                settings: settings,
                                voiceSettings: voiceSettings,
                                permissionState: permissionState,
                                captureController: captureController,
                                onSettingsChanged: onSettingsChanged
                            )
                        case .permissions:
                            SettingsPermissionsPane(
                                permissionState: permissionState,
                                onShowAccessibilityHelper: onShowAccessibilityHelper
                            )
                        }
                    }
                    .padding(16)
                    // The sidebar names the pane, so content starts level
                    // with the first sidebar row instead of under a title.
                    .padding(.top, Self.titleBarHeight - 16)
                    .frame(maxWidth: Self.contentMaxWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .id(tab)
                }
                .scrollIndicators(.automatic)
                if showsFooter {
                    Divider()
                    footer
                }
            }
        }
        .frame(
            minWidth: Self.size.width, maxWidth: .infinity,
            minHeight: Self.size.height, maxHeight: .infinity
        )
        .background(PaletteTint.surface(colorScheme))
        .ignoresSafeArea()
        .overlayScrollers()
        .tint(Color.primary.opacity(0.85))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !footerContext.isEmpty {
                Text(footerContext)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            footerActions
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private var showsFooter: Bool {
        !footerContext.isEmpty || hasFooterActions
    }

    private var hasFooterActions: Bool {
        switch tab {
        case .capture: !permissionState.isVoiceReady
        case .shortcuts: false
        case .templates: templateEditor.isDirty
        case .permissions: permissionsFooterAction != nil
        }
    }

    private var footerContext: String {
        switch tab {
        case .templates:
            templateEditor.isDirty ? "Unsaved" : ""
        default:
            ""
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        switch tab {
        case .capture:
            if !permissionState.isVoiceReady {
                SettingsFooterButton("Permissions") { tab = .permissions }
            }
        case .shortcuts:
            EmptyView()
        case .templates:
            templateFooterActions
        case .permissions:
            if let action = permissionsFooterAction {
                SettingsFooterButton(action.title, action: action.run)
            }
        }
    }

    @ViewBuilder
    private var templateFooterActions: some View {
        if templateEditor.isDirty {
            Button("Revert", action: templateEditor.revert)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
            SettingsFooterButton("Save", keys: "⌘S") { saveTemplate() }
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private var permissionsFooterAction: (title: String, run: () -> Void)? {
        if let title = accessibilityFooterTitle {
            return (title, { [onShowAccessibilityHelper, permissionState] in
                switch permissionState.accessibilityAction {
                case .requestAccessibility:
                    permissionState.requestAccessibility()
                    onShowAccessibilityHelper()
                case .showAccessibilityHelper:
                    onShowAccessibilityHelper()
                default:
                    break
                }
            })
        }
        switch permissionState.microphoneAction {
        case .requestMicrophone:
            return ("Allow", { permissionState.requestMicrophone() })
        case .openMicrophoneSettings:
            return ("Settings", { permissionState.openMicrophoneSettings() })
        default:
            break
        }
        if permissionState.localVoiceModelAction == .downloadVoiceModel {
            let title: String
            if case .failed = permissionState.localVoiceModel {
                title = "Retry"
            } else {
                title = "Download"
            }
            return (title, { permissionState.downloadModel() })
        }
        return nil
    }

    private var accessibilityFooterTitle: String? {
        switch permissionState.accessibilityAction {
        case .requestAccessibility, .showAccessibilityHelper: "Grant"
        default: nil
        }
    }

    private func saveTemplate() {
        do { try templateEditor.save() } catch { TemplateDialogs.showError(error) }
    }
}

/// A small anchored prompt: type a name, press Return.
struct NewTemplatePopover: View {
    @Binding var name: String
    let problem: String?
    let onCommit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New template from the current draft")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Template name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(onCommit)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ShortcutHint(keys: "↩", label: "Create")
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

// MARK: - Building blocks

/// A row of pills that fill from the left as the microphone gets louder.
struct InputLevelBar: View {
    let level: Float
    let isActive: Bool

    private let segments = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < litSegments ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12))
                    .frame(height: 8)
            }
        }
        .opacity(isActive ? 1 : 0.5)
        .animation(.linear(duration: 0.05), value: litSegments)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(isActive ? "\(Int(level * 100)) percent" : "Not listening")
    }

    private var litSegments: Int {
        guard isActive else { return 0 }
        return Int((level * Float(segments)).rounded())
    }
}

/// Tells SwiftUI whether the window it lives in is actually on screen, so
/// live work like the level meter stops when the window is hidden.
struct WindowVisibilityReporter: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onChange = { isVisible = $0 }
    }

    final class ReporterView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { report(false); return }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.reportCurrent() } })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.report(false) } })
            reportCurrent()
        }

        private func reportCurrent() {
            guard let window else { report(false); return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            DispatchQueue.main.async { [onChange] in onChange?(visible) }
        }
    }
}

/// A native pop-up so it fills the width it is given; SwiftUI's menu picker
/// sizes itself to its title instead. The menu shows every title in full
/// with a checkmark on the current item.
struct SettingsPopUp<ID: Hashable>: NSViewRepresentable {
    struct Item {
        var id: ID?
        var title: String
        var isSeparator = false

        static var separator: Item { Item(id: nil, title: "", isSeparator: true) }
    }

    let items: [Item]
    let selectedID: ID?
    let onSelect: (ID?) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = SettingsPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.autoenablesItems = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if menuDiffers(from: button) {
            button.removeAllItems()
            for item in items {
                if item.isSeparator {
                    button.menu?.addItem(.separator())
                } else {
                    let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                    if let id = item.id {
                        menuItem.representedObject = id
                    }
                    button.menu?.addItem(menuItem)
                }
            }
        }
        let index = button.itemArray.firstIndex {
            !$0.isSeparatorItem && ($0.representedObject as? ID) == selectedID
        } ?? 0
        if button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    private func menuDiffers(from button: NSPopUpButton) -> Bool {
        let current = button.itemArray
        guard current.count == items.count else { return true }
        return zip(current, items).contains { menuItem, item in
            if item.isSeparator { return !menuItem.isSeparatorItem }
            return menuItem.isSeparatorItem
                || menuItem.title != item.title
                || (menuItem.representedObject as? ID) != item.id
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    final class Coordinator: NSObject {
        var onSelect: (ID?) -> Void

        init(onSelect: @escaping (ID?) -> Void) { self.onSelect = onSelect }

        @objc func changed(_ sender: NSPopUpButton) {
            onSelect(sender.selectedItem?.representedObject as? ID)
        }
    }
}

/// Intrinsic width would shrink to the title; SwiftUI needs a flexible width.
private final class SettingsPopUpButton: NSPopUpButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}

/// The source list on the left. Selected pane uses the same wash and 3px
/// rail as a stack row.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    let topInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarRow(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .background(PaletteTint.wash(highlighted: isSelected, hovering: hovering))
        .overlay(alignment: .leading) {
            if isSelected {
                PaletteTint.FocusRail()
            }
        }
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The template's name as a form field. Trailing sits on the name line and
/// shares the rule's right edge.
struct TemplateNameField<Trailing: View>: View {
    @Binding var text: String
    @ViewBuilder var trailing: () -> Trailing
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Name", text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focused)
                    .accessibilityLabel("Template name")
                    .layoutPriority(1)
                trailing()
            }
            Rectangle()
                .fill(Color.primary.opacity(focused ? 0.5 : 0.1))
                .frame(height: 1)
        }
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Footer-weight icon: secondary until the pointer is on it.
struct QuietIconButton: View {
    let systemName: String
    var hoverColor: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    init(_ systemName: String, hoverColor: Color = .primary, action: @escaping () -> Void) {
        self.systemName = systemName
        self.hoverColor = hoverColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? hoverColor : Color.secondary)
        .onHover { hovering = $0 }
    }
}

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
        guard let stored = editor.storedTemplate,
              StackDialogs.confirmsDeletion(of: stored.name, informative: "This cannot be undone.")
        else { return }
        do {
            try editor.delete()
        } catch {
            showError(error)
        }
    }

    static func showError(_ error: Error) {
        StackDialogs.inform(title: "Couldn't Change Template", message: error.localizedDescription)
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
