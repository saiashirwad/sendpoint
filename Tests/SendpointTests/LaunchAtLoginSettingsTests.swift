import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class LaunchAtLoginSettingsTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testLaunchAtLoginFollowsTheLoginItemRegistrationOutcome() {
        let suite = "LaunchAtLoginSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var registerCount = 0
        var shouldFail = true
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: {
                registerCount += 1
                if shouldFail { throw TestError.failed }
            },
            unregisterLoginItem: {}
        )
        settings.setLaunchAtLogin(false)

        settings.setLaunchAtLogin(true)
        XCTAssertFalse(settings.launchAtLogin, "a failed registration rolls the toggle back")

        shouldFail = false
        settings.setLaunchAtLogin(true)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(registerCount, 2)
    }
}
