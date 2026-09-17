import SwiftUI

struct SettingsCapturePane: View {
    @Bindable var shortcuts: ShortcutSettings
    @Bindable var voiceSettings: VoiceSettings
    let hotKeyRegistrar: HotKeyRegistrar
    let captureController: CaptureController
    let onSettingsChanged: () -> Void

    @State private var inputDevices = AudioInputDeviceList()
    @State private var preview = MicrophonePreviewOwner()
    @State private var windowIsVisible = false

    var body: some View {
        SettingsPage {
            SettingsSection("Recording", footnote: voiceSettings.voiceMode.detail) {
                SettingsStackedRow {
                    ChoiceChips(
                        values: Array(VoiceRecordingMode.allCases),
                        selection: Binding(
                            get: { voiceSettings.voiceMode },
                            set: { captureController.setVoiceMode($0) }
                        ),
                        title: { $0.title }
                    )
                }
            }
            SettingsSection("Microphone", footnote: microphoneFootnote) {
                SettingsStackedRow {
                    VStack(alignment: .leading, spacing: 12) {
                        microphoneMenu
                        InputLevelBar(level: preview.level, isActive: preview.isActive)
                            .frame(width: 300)
                    }
                }
            }
            SettingsSection("Shortcuts") {
                ShortcutRows(
                    specs: [
                        ShortcutSpec(title: "Voice note", hint: "Saves what you say to the stack", slot: .voiceCapture),
                        ShortcutSpec(title: "Typed note", hint: "Quotes the selected text", slot: .capture),
                        ShortcutSpec(title: "Dictate", hint: "Pastes what you say at the cursor", slot: .dictate),
                    ],
                    shortcuts: shortcuts,
                    hotKeyRegistrar: hotKeyRegistrar,
                    onSettingsChanged: onSettingsChanged
                )
            }
        }
        .background(WindowVisibilityReporter(isVisible: $windowIsVisible))
        .onAppear { syncPreview() }
        .onDisappear { preview.stop() }
        .onChange(of: voiceSettings.inputDeviceUID) { _, _ in syncPreview() }
        .onChange(of: windowIsVisible) { _, _ in syncPreview() }
    }

    private func syncPreview() {
        if windowIsVisible {
            preview.start(uid: voiceSettings.inputDeviceUID)
        } else {
            preview.stop()
        }
    }

    private var microphoneFootnote: String? {
        guard voiceSettings.inputDeviceUID != nil, !selectedDeviceIsConnected else { return nil }
        return "\(voiceSettings.inputDeviceName ?? "That microphone") is not connected, so the system default is used."
    }

    private var selectedDeviceIsConnected: Bool {
        guard let uid = voiceSettings.inputDeviceUID else { return true }
        return inputDevices.devices.contains { $0.uid == uid }
    }

    private var selectedTitle: String {
        if let uid = voiceSettings.inputDeviceUID {
            return inputDevices.devices.first { $0.uid == uid }?.name
                ?? voiceSettings.inputDeviceName
                ?? "Saved microphone"
        }
        return systemDefaultLabel
    }

    private var systemDefaultLabel: String {
        guard let name = inputDevices.systemDefault?.name else { return "System default" }
        return "System default · \(name)"
    }

    private var microphoneMenu: some View {
        ChoiceMenu<String?, _>(title: selectedTitle, width: 300) {
            Picker("Microphone", selection: Binding<String?>(
                get: { voiceSettings.inputDeviceUID },
                set: { uid in
                    captureController.chooseMicrophone(uid: uid, devices: inputDevices.devices)
                }
            )) {
                Text(systemDefaultLabel).tag(String?.none)
                if !inputDevices.devices.isEmpty {
                    Divider()
                    ForEach(inputDevices.devices, id: \.uid) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                if let uid = voiceSettings.inputDeviceUID, !selectedDeviceIsConnected {
                    Divider()
                    Text("\(voiceSettings.inputDeviceName ?? "Saved microphone") (not connected)")
                        .tag(String?.some(uid))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .accessibilityLabel("Microphone")
    }
}

struct InputLevelBar: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: max(0, proxy.size.width * CGFloat(isActive ? min(max(level, 0), 1) : 0)))
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
        .frame(height: 3)
        .opacity(isActive ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(isActive ? "\(Int(level * 100)) percent" : "Not listening")
    }
}
