import AppKit

@MainActor
private enum AppKitTestApplication {
    static let initialized: Void = {
        NSApplication.shared.finishLaunching()
    }()
}

@MainActor
func initializeAppKitTestApplication() {
    _ = AppKitTestApplication.initialized
}
