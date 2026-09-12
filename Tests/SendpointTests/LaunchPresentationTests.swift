import XCTest
@testable import Sendpoint

@MainActor
final class LaunchPresentationTests: XCTestCase {
    func testIncompleteSetupAlwaysPresentsSetup() {
        XCTAssertEqual(LaunchPresentation.decide(hasCompletedSetup: false, kind: .login), .setup)
        XCTAssertEqual(LaunchPresentation.decide(hasCompletedSetup: false, kind: .userOpen), .setup)
    }

    func testLoginLaunchStaysInTheMenuBarOnceSetupIsDone() {
        XCTAssertEqual(LaunchPresentation.decide(hasCompletedSetup: true, kind: .login), .none)
    }

    func testUserOpenPresentsSettingsOnceSetupIsDone() {
        XCTAssertEqual(LaunchPresentation.decide(hasCompletedSetup: true, kind: .userOpen), .settings)
    }

    func testOpenApplicationWithoutLoginPropertyIsUserOpen() {
        XCTAssertEqual(
            LaunchPresentation.Kind.from(
                eventID: LaunchPresentation.Kind.openApplicationEventID,
                loginItemProperty: nil
            ),
            .userOpen
        )
    }

    func testLoginItemAppleEventIsLogin() {
        XCTAssertEqual(
            LaunchPresentation.Kind.from(
                eventID: LaunchPresentation.Kind.openApplicationEventID,
                loginItemProperty: LaunchPresentation.Kind.launchedAsLoginItem
            ),
            .login
        )
    }

    func testMissingOrUnrelatedAppleEventIsUserOpen() {
        XCTAssertEqual(LaunchPresentation.Kind.from(eventID: nil, loginItemProperty: nil), .userOpen)
        XCTAssertEqual(
            LaunchPresentation.Kind.from(
                eventID: 0x72617070, // 'rapp'
                loginItemProperty: LaunchPresentation.Kind.launchedAsLoginItem
            ),
            .userOpen
        )
    }
}
