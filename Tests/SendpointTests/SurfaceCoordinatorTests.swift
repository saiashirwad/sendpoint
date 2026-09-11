import XCTest
@testable import Sendpoint

@MainActor
final class SurfaceCoordinatorTests: XCTestCase {
    func testCaptureEditorHidesAuxiliarySurfaces() {
        let spy = Spy()
        let coordinator = makeCoordinator(spy: spy)
        coordinator.present(.palette)
        coordinator.present(.settings)
        coordinator.present(.setup)
        coordinator.present(.accessibilityHelper)
        spy.events.removeAll()

        coordinator.present(.captureEditor)

        XCTAssertEqual(spy.events, [
            "hide palette", "hide settings", "hide setup", "hide accessibilityHelper",
            "show captureEditor",
        ])
        XCTAssertEqual(coordinator.visible, [.captureEditor])
    }

    func testSwitcherHidesPaletteAndBlocksItsReopen() {
        let spy = Spy()
        let coordinator = makeCoordinator(spy: spy)
        coordinator.present(.palette)
        coordinator.present(.switcher)
        coordinator.present(.palette)

        XCTAssertEqual(spy.events, ["show palette", "hide palette", "show switcher"])
        XCTAssertEqual(coordinator.visible, [.switcher])
    }

    func testUserCloseUpdatesAppliedState() {
        let spy = Spy()
        let coordinator = makeCoordinator(spy: spy)
        coordinator.present(.settings)

        coordinator.userClosed(.settings)

        XCTAssertFalse(coordinator.visible.contains(.settings))
        XCTAssertEqual(spy.events, ["show settings"])
    }

    func testModalWindowSuppressesResignKey() {
        let spy = Spy()
        var modal = true
        let coordinator = makeCoordinator(spy: spy, hasModalWindow: { modal })
        coordinator.present(.palette)

        coordinator.resignedKey(.palette)
        XCTAssertTrue(coordinator.visible.contains(.palette))

        modal = false
        coordinator.resignedKey(.palette)
        XCTAssertFalse(coordinator.visible.contains(.palette))
        XCTAssertEqual(spy.events, ["show palette", "hide palette"])
    }

    func testPaletteShowTransitionRunsAgainAfterDismissal() {
        var query = "first"
        var highlights = 8
        let coordinator = SurfaceCoordinator(hasModalWindow: { false })
        coordinator.register(.palette, transitions: .init(
            show: { query = ""; highlights = 0 },
            hide: {}
        ))

        coordinator.present(.palette)
        query = "second"
        highlights = 3
        coordinator.dismiss(.palette)
        coordinator.present(.palette)

        XCTAssertEqual(query, "")
        XCTAssertEqual(highlights, 0)
    }

    private func makeCoordinator(
        spy: Spy,
        hasModalWindow: @escaping () -> Bool = { false }
    ) -> SurfaceCoordinator {
        let coordinator = SurfaceCoordinator(hasModalWindow: hasModalWindow)
        for surface in Surface.allCases {
            coordinator.register(surface, transitions: .init(
                show: { spy.events.append("show \(surface)") },
                hide: { spy.events.append("hide \(surface)") }
            ))
        }
        return coordinator
    }

    private final class Spy {
        var events: [String] = []
    }
}
