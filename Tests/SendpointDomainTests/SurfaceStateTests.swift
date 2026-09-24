import XCTest
import SendpointDomain

final class SurfaceStateTests: XCTestCase {
    func testCaptureEditorHidesPaletteAndSettingsButNotSetup() {
        var state = SurfaceState()
        _ = state.update(.present(.palette, registered: true))
        _ = state.update(.present(.settings, registered: true))
        _ = state.update(.present(.setup, registered: true))

        XCTAssertEqual(
            state.update(.present(.captureEditor, registered: true)),
            [
                .hide(.palette), .hide(.settings), .setRegularActivation(false),
                .show(.captureEditor),
            ]
        )
        XCTAssertEqual(state.visible, [.captureEditor, .setup])
    }

    func testOnlySettingsRequestsRegularActivation() {
        var state = SurfaceState()
        for surface in [Surface.palette, .setup, .captureEditor, .captureVoice] {
            XCTAssertFalse(
                state.update(.present(surface, registered: true)).contains(.setRegularActivation(true))
            )
        }

        XCTAssertEqual(
            state.update(.present(.settings, registered: true)),
            [.setRegularActivation(true), .show(.settings)]
        )
        XCTAssertTrue(state.update(.dismiss(.settings)).contains(.setRegularActivation(false)))
    }

    func testActivationChangesBeforeShowAndAfterHide() {
        var state = SurfaceState()

        XCTAssertEqual(
            state.update(.present(.settings, registered: true)),
            [.setRegularActivation(true), .show(.settings)]
        )
        XCTAssertEqual(
            state.update(.dismiss(.settings)),
            [.hide(.settings), .setRegularActivation(false)]
        )
    }

    func testUserCloseRemovesTheSurfaceWithoutHidingIt() {
        var state = SurfaceState()
        _ = state.update(.present(.settings, registered: true))

        XCTAssertEqual(state.update(.userClosed(.settings)), [.setRegularActivation(false)])
        XCTAssertFalse(state.visible.contains(.settings))
    }

    func testModalResignDoesNothingUntilTheModalIsGone() {
        var state = SurfaceState()
        _ = state.update(.present(.palette, registered: true))

        XCTAssertEqual(state.update(.resignedKey(.palette, modal: true)), [])
        XCTAssertTrue(state.visible.contains(.palette))
        XCTAssertEqual(state.update(.resignedKey(.palette, modal: false)), [.hide(.palette)])
        XCTAssertFalse(state.visible.contains(.palette))
    }

    func testDismissedSurfaceCanBeShownAgain() {
        var state = SurfaceState()
        _ = state.update(.present(.palette, registered: true))
        _ = state.update(.dismiss(.palette))

        XCTAssertEqual(state.update(.present(.palette, registered: true)), [.show(.palette)])
        XCTAssertEqual(state.visible, [.palette])
    }

    func testUnregisteredCaptureStillDismissesButDoesNotShow() {
        var state = SurfaceState()
        _ = state.update(.present(.palette, registered: true))

        XCTAssertEqual(state.update(.present(.captureEditor, registered: false)), [.hide(.palette)])
        XCTAssertEqual(state.visible, [])
    }

    func testSecondTeardownDoesNothing() {
        var state = SurfaceState()
        _ = state.update(.present(.settings, registered: true))
        XCTAssertEqual(
            state.update(.teardown),
            [.hide(.settings), .setRegularActivation(false)]
        )

        XCTAssertEqual(state.update(.teardown), [])
        XCTAssertEqual(state.update(.present(.palette, registered: true)), [])
        XCTAssertTrue(state.isTornDown)
        XCTAssertFalse(state.visible.contains(.settings))
    }
}
