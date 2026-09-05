import Foundation

extension ProvenanceProvider {
    /// Browsers that answer the Chromium AppleScript dictionary. Asking one for
    /// its active tab triggers the macOS Automation prompt for that browser once.
    static let chromiumBundleIDs: Set<String> = [
        "net.imput.helium",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
        "com.google.Chrome.canary", "org.chromium.Chromium",
        "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
    ]

    static let safariBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]

    static let chromiumBrowsers = browser(bundleIDs: chromiumBundleIDs) {
        BrowserActiveTabScript.chromium(bundleID: $0)
    }
    static let safariBrowsers = browser(bundleIDs: safariBundleIDs) {
        BrowserActiveTabScript.safari(bundleID: $0)
    }

    private static func browser(
        bundleIDs: Set<String>,
        script: @escaping @Sendable (String) -> String
    ) -> Self {
        Self(bundleIDs: bundleIDs) { application in
            guard let bundleID = application.identity.bundleID else { return ProvenanceFields() }
            let values = try await ProvenanceSystemBoundary.appleScriptValues(script(bundleID))
            return BrowserActiveTabParser.fields(from: values ?? [])
        }
    }
}

/// Read-only scripts. The probe validates the captured running application before execution.
enum BrowserActiveTabScript {
    static func chromium(bundleID: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                if not (exists front window) then return {}
                set selectedTab to active tab of front window
                return {title of selectedTab as text, URL of selectedTab as text}
            end tell
        end timeout
        """
    }

    static func safari(bundleID: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                if not (exists front window) then return {}
                set selectedTab to current tab of front window
                return {name of selectedTab as text, URL of selectedTab as text}
            end tell
        end timeout
        """
    }
}

enum BrowserActiveTabParser {
    static func fields(from values: [String]) -> ProvenanceFields {
        guard values.count == 2 else { return ProvenanceFields() }
        return ProvenanceFields(windowTitle: nonblank(values[0]), url: absoluteWebURL(values[1]))
    }

    private static func nonblank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func absoluteWebURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              let url = components.url,
              !url.isFileURL
        else { return nil }
        return url
    }
}

