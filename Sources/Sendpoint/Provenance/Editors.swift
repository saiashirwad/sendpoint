
extension ProvenanceProvider {
    static let codeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodeExploration", "com.visualstudio.code.oss",
        "com.vscodium", "com.vscodium.VSCodium", "com.vscodium.VSCodiumInsiders",
        "com.todesktop.230313mzl4w4u92", "co.anysphere.cursor.nightly",
        "com.exafunction.windsurf", "com.google.antigravity",
        "com.google.antigravity-ide", "com.t3tools.t3code", "com.trae.app",
        "dev.zed.Zed", "dev.zed.Zed-Preview",
    ]

    static let codeEditors = Self(bundleIDs: codeEditorBundleIDs) { application in
        try await ProvenanceSystemBoundary.codeEditorFields(
            processIdentifier: application.processIdentifier
        )
    }
}
