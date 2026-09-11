import SwiftUI

struct SettingsPermissionsPane: View {
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsSection("Permissions") {
                PermissionCapabilityList(
                    permissionState: permissionState,
                    onShowAccessibilityHelper: onShowAccessibilityHelper
                )
            }
        }
    }
}
