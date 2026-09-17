import Sparkle

/// Owns Sparkle for the app's lifetime. Sparkle schedules background checks
/// and installs a verified update when the app next has a safe opportunity.
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
