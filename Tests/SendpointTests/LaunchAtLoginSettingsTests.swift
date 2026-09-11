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
        let registrar = Registrar()
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: { try registrar.register() },
            unregisterLoginItem: {}
        )
        settings.setLaunchAtLogin(false)

        settings.setLaunchAtLogin(true)
        XCTAssertFalse(settings.launchAtLogin, "a failed registration rolls the toggle back")

        registrar.shouldFail = false
        settings.setLaunchAtLogin(true)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(registrar.count, 2)
    }

    private final class Registrar {
        var shouldFail = true
        var count = 0

        func register() throws {
            count += 1
            if shouldFail { throw TestError.failed }
        }
    }
}
