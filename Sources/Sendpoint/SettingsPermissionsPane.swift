import SwiftUI

struct SettingsPermissionsPane: View {
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void

    var body: some View {
        SettingsRowGroup {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    SettingsDivider(pastIcon: false)
                }
                SettingsIconRow(title: item.title, detail: item.detail) {
                    accessory(item)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.actionTitle ?? item.status.title)
                .accessibilityAddTraits(item.actionTitle == nil ? [] : .isButton)
            }
        }
        .task { await permissionState.watchVoiceModel() }
    }

    private var items: [PermissionItem] {
        PermissionCatalog.items(
            state: permissionState,
            onShowAccessibilityHelper: onShowAccessibilityHelper
        )
    }

    @ViewBuilder
    private func accessory(_ item: PermissionItem) -> some View {
        if item.actionTitle != nil {
            Button(action: item.run) {
                CapabilityAccessory(status: item.status, actionTitle: item.actionTitle)
            }
            .buttonStyle(.plain)
        } else {
            CapabilityAccessory(status: item.status)
        }
    }
}
