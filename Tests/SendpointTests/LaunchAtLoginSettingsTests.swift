import Foundation
import XCTest
@testable import Sendpoint

@MainActor
final class LaunchAtLoginSettingsTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testFailedRegisterKeepsLaunchAtLoginOff() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: { throw TestError.failed },
            unregisterLoginItem: {}
        )
        settings.setLaunchAtLogin(false)
        XCTAssertFalse(settings.launchAtLogin)

        settings.setLaunchAtLogin(true)

        XCTAssertFalse(settings.launchAtLogin)
    }

    func testSuccessfulRegisterTurnsLaunchAtLoginOn() {
        let defaults = makeDefaults()
        defer { remove(defaults) }
        var registerCount = 0
        let settings = AppSettings(
            defaults: defaults,
            registerLoginItem: { registerCount += 1 },
            unregisterLoginItem: {}
        )
        settings.setLaunchAtLogin(false)
        XCTAssertFalse(settings.launchAtLogin)

        settings.setLaunchAtLogin(true)

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(registerCount, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LaunchAtLoginSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(suite, forKey: "testSuiteName")
        return defaults
    }

    private func remove(_ defaults: UserDefaults) {
        guard let suite = defaults.string(forKey: "testSuiteName") else { return }
        defaults.removePersistentDomain(forName: suite)
    }
}
