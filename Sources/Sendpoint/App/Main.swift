import AppKit

@main
enum Main {
    private static let delegate = AppDelegate()
    static func main() {
        if ProcessInfo.processInfo.environment["SENDPOINT_ALLOW_MULTIPLE"] != "1",
           let bundleID = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            LaunchPresentation.notifyRunningInstance(bundleIdentifier: bundleID)
            running.activate()
            exit(0)
        }

        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")

        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
