import SwiftUI

struct SettingsPermissionsPane: View {
    @Bindable var permissionState: PermissionState
    let onShowAccessibilityHelper: () -> Void

    var body: some View {
        PermissionCapabilityList(
            permissionState: permissionState,
            onShowAccessibilityHelper: onShowAccessibilityHelper
        )
    }
}
