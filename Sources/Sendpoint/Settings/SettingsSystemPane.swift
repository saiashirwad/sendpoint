import SwiftUI

struct SettingsSystemPane: View {
    @Bindable var settings: AppSettings
    @Bindable var permissionState: PermissionState
    let onSettingsChanged: () -> Void
    let onCheckForUpdates: () -> Void

    var body: some View {
        SettingsPage {
            SettingsSection("Startup") {
                SettingsToggleRow(
                    "Launch at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: {
                            settings.send(.launchAtLogin($0))
                            onSettingsChanged()
                        }
                    )
                )
            }
            SettingsSection("Permissions", footnote: "Audio never leaves this Mac.") {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(item.title, hint: item.detail) {
                        CapabilityAccessory(status: item.status, actionTitle: item.actionTitle, action: item.run)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.actionTitle ?? item.status.title)
                }
            }
            SettingsSection("Updates") {
                SettingsRow("Sendpoint", hint: AppVersion.display) {
                    PillButton("Check for updates", action: onCheckForUpdates)
                }
            }
        }
    }

    private var items: [PermissionItem] {
        PermissionCatalog.items(state: permissionState)
    }
}

enum AppVersion {
    static var display: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        if let build = info?["CFBundleVersion"] as? String, build != version {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }
}
