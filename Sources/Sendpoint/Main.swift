import AppKit

@main
enum Main {
    /// NSApplication.delegate is weak, so this is the one strong reference.
    private static let delegate = AppDelegate()
    static func main() {
        // Two copies would take turns overwriting store.json.
        // SENDPOINT_ALLOW_MULTIPLE=1 lets a development build run beside the installed one.
        if ProcessInfo.processInfo.environment["SENDPOINT_ALLOW_MULTIPLE"] != "1",
           let bundleID = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            LaunchPresentation.notifyRunningInstance(bundleIdentifier: bundleID)
            running.activate()
            exit(0)
        }

        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
