import SwiftUI

struct SettingsGeneralPane: View {
    @Bindable var settings: AppSettings
    @Bindable var voiceSettings: VoiceSettings
    @Bindable var permissionState: PermissionState
    let captureController: CaptureController
    let onOpenPermissions: () -> Void
    let onSettingsChanged: () -> Void

    @State private var inputDevices = AudioInputDeviceList()
    @State private var levelMonitor = InputLevelMonitor()
    @State private var windowIsVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            voiceSection
            microphoneSection
            behaviorSection
        }
        .background(WindowVisibilityReporter(isVisible: $windowIsVisible))
        .task { await permissionState.watchVoiceModel() }
        .task(id: levelMonitorKey) {
            guard windowIsVisible else {
                levelMonitor.stop()
                return
            }
            levelMonitor.start(preferredUID: voiceSettings.inputDeviceUID)
        }
        .onDisappear { levelMonitor.stop() }
    }

    private var voiceSection: some View {
        SettingsSection("Voice") {
            SettingsRowGroup {
                SettingsIconRow(
                    icon: "hand.tap",
                    title: "Recording mode",
                    detail: "How the shortcut starts and stops a recording."
                ) {
                    Picker("Recording mode", selection: Binding(
                        get: { voiceSettings.voiceMode },
                        set: { captureController.setVoiceMode($0) }
                    )) {
                        ForEach(VoiceRecordingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if !permissionState.isVoiceReady {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Voice needs a permission.")
                    Button("Open Permissions", action: onOpenPermissions)
                        .buttonStyle(.link)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            }
        }
    }

    private var microphoneSection: some View {
        SettingsSection("Microphone") {
            microphonePicker
            InputLevelBar(level: levelMonitor.level, isActive: levelMonitor.isRunning)
            Text(microphoneFootnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var behaviorSection: some View {
        SettingsSection("Behavior") {
            SettingsRowGroup {
                SettingsToggleRow(
                    "Paste straight into the app you are in",
                    subtitle: "The Markdown lands where your cursor is, without a separate paste.",
                    isOn: Binding(
                        get: { settings.pasteDirectly },
                        set: {
                            settings.setPasteDirectly($0)
                            onSettingsChanged()
                        }
                    )
                )
                SettingsDivider(pastIcon: false)
                SettingsToggleRow(
                    "Return to the previous app after saving",
                    subtitle: "Hands focus back to where you were reading.",
                    isOn: Binding(
                        get: { settings.restoreFocusAfterSave },
                        set: {
                            settings.setRestoreFocusAfterSave($0)
                            onSettingsChanged()
                        }
                    )
                )
                SettingsDivider(pastIcon: false)
                SettingsToggleRow(
                    "Launch at login",
                    subtitle: "Keeps the shortcuts ready as soon as you sign in.",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: {
                            settings.setLaunchAtLogin($0)
                            onSettingsChanged()
                        }
                    )
                )
            }
        }
    }

    private var levelMonitorKey: String {
        "\(windowIsVisible)|\(voiceSettings.inputDeviceUID ?? "default")|\(permissionState.microphone == .granted)"
    }

    private var microphoneFootnote: String {
        if voiceSettings.inputDeviceUID != nil, !selectedDeviceIsConnected {
            return "\(voiceSettings.inputDeviceName ?? "That microphone") is not connected, so the system default is used."
        }
        return "The built-in microphone usually sounds better than AirPods."
    }

    private var selectedDeviceIsConnected: Bool {
        guard let uid = voiceSettings.inputDeviceUID else { return true }
        return inputDevices.devices.contains { $0.uid == uid }
    }

    private var microphonePicker: some View {
        var items: [InputDevicePopUp.Item] = [.init(uid: nil, title: systemDefaultLabel)]
        if !inputDevices.devices.isEmpty {
            items.append(.separator)
            items += inputDevices.devices.map { .init(uid: $0.uid, title: $0.name) }
        }
        if let uid = voiceSettings.inputDeviceUID, !selectedDeviceIsConnected {
            items.append(.separator)
            items.append(.init(
                uid: uid,
                title: "\(voiceSettings.inputDeviceName ?? "Saved microphone") (not connected)"
            ))
        }
        return InputDevicePopUp(items: items, selectedUID: voiceSettings.inputDeviceUID) { uid in
            let name = inputDevices.devices.first { $0.uid == uid }?.name
            captureController.chooseMicrophone(uid: uid, name: name)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Microphone")
    }

    private var systemDefaultLabel: String {
        guard let name = inputDevices.systemDefault?.name else { return "System default" }
        return "System default (\(name))"
    }
}
