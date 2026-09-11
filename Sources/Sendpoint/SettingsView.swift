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

    var icon: String {
        switch self {
        case .shortcuts: "keyboard.fill"
        case .templates: "text.quote"
        case .capture: "gearshape.fill"
        case .permissions: "checkmark.shield.fill"
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

    /// The smallest the window goes; it can be dragged larger.
    static let size = CGSize(width: 780, height: 620)
    private static let sidebarWidth: CGFloat = 200
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
                                onOpenPermissions: { tab = .permissions },
                                onSettingsChanged: onSettingsChanged
                            )
                        case .permissions:
                            SettingsPermissionsPane(
                                permissionState: permissionState,
                                onShowAccessibilityHelper: onShowAccessibilityHelper
                            )
                        }
                    }
                    .padding(24)
                    // The sidebar names the pane, so content starts level
                    // with the first sidebar row instead of under a title.
                    .padding(.top, Self.titleBarHeight - 24)
                    .frame(maxWidth: Self.contentMaxWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                    .id(tab)
                }
                .scrollIndicators(.automatic)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: Self.size.width, maxWidth: .infinity,
            minHeight: Self.size.height, maxHeight: .infinity
        )
        .ignoresSafeArea()
        .overlayScrollers()
        // Monochrome controls: an "on" toggle or selected segment takes the
        // text colour; off states keep the system grey.
        .tint(Color.primary.opacity(0.85))
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

/// The input meter from System Settings: a row of pills that fill from the
/// left as the microphone gets louder.
struct InputLevelBar: View {
    let level: Float
    let isActive: Bool

    private let segments = 24

    var body: some View {
        HStack(spacing: 8) {
            Text("Input level")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < litSegments ? Color.green : Color.primary.opacity(0.12))
                        .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 2)
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
/// sizes itself to its title instead.
struct InputDevicePopUp: NSViewRepresentable {
    struct Item {
        var uid: String?
        var title: String
        var isSeparator = false

        static let separator = Item(uid: nil, title: "", isSeparator: true)
    }

    let items: [Item]
    let selectedUID: String?
    let onSelect: (String?) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.removeAllItems()
        for item in items {
            if item.isSeparator {
                button.menu?.addItem(.separator())
            } else {
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                menuItem.representedObject = item.uid
                button.menu?.addItem(menuItem)
            }
        }
        let index = button.itemArray.firstIndex { ($0.representedObject as? String) == selectedUID && !$0.isSeparatorItem }
        button.selectItem(at: index ?? 0)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    final class Coordinator: NSObject {
        var onSelect: (String?) -> Void

        init(onSelect: @escaping (String?) -> Void) { self.onSelect = onSelect }

        @objc func changed(_ sender: NSPopUpButton) {
            onSelect(sender.selectedItem?.representedObject as? String)
        }
    }
}

/// A round, quiet icon button for secondary actions beside a title.
struct CircleIconButton: View {
    let icon: String
    let help: String
    let label: String
    let action: () -> Void

    init(_ icon: String, help: String, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The source list on the left, with a coloured tile per section.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    let topInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: topInset)
            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarRow(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            SidebarMaterial()
                // Light mode: wash the material toward white so the pane
                // reads as paper and the selected row carries the contrast.
                .overlay(Color.white.opacity(colorScheme == .dark ? 0 : 0.6))
                .ignoresSafeArea()
        )
    }
}

private struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    /// Light mode needs a heavier wash for the row to read as selected.
    private var selectedOpacity: Double { colorScheme == .dark ? 0.09 : 0.14 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SidebarTile(icon: tab.icon, isSelected: isSelected)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? selectedOpacity : hovering ? 0.04 : 0))
        )
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A monochrome tile: a faint fill, a hairline rim, and a glyph that takes
/// the row's text colour so every section reads as one set.
private struct SidebarTile: View {
    let icon: String
    let isSelected: Bool

    private let shape = RoundedRectangle(cornerRadius: 6.5, style: .continuous)

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(shape.fill(Color.primary.opacity(isSelected ? 0.12 : 0.07)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

struct TemplateChip: View {
    let name: String
    let isSelected: Bool
    let isDirty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if isDirty {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Unsaved changes")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                Capsule().fill(Color.primary.opacity(isSelected ? 0.14 : 0.06))
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The template's name, set as an editable title rather than a form field.
struct TemplateNameField<Accessory: View>: View {
    @Binding var text: String
    @ViewBuilder let accessory: () -> Accessory
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Template name", text: $text)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .focused($focused)
                    .accessibilityLabel("Template name")
                accessory()
            }
            .frame(minHeight: 24)
            Rectangle()
                .fill(Color.primary.opacity(focused ? 0.5 : 0.1))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.15), value: focused)
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
