import AppKit
import SendpointDomain

/// Caches app icons by bundle ID. A hit is remembered, and so is a miss, so
/// an app that cannot be found costs one lookup rather than one per render.
final class AppIconStore {
    static let shared = AppIconStore()

    private let load: @MainActor (String) -> NSImage?
    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []

    init(load: @escaping @MainActor (String) -> NSImage? = { bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            let icon = NSWorkspace.shared.icon(forFile: $0.path)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
    }) {
        self.load = load
    }

    func icon(for application: ApplicationIdentity) -> NSImage? {
        guard let bundleID = application.bundleID?.nonblank else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard !missing.contains(bundleID) else { return nil }
        guard let image = load(bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        icons[bundleID] = image
        return image
    }
}
