import AppKit

@main
enum Main {
    /// NSApplication.delegate is weak, so this is the one strong reference.
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
