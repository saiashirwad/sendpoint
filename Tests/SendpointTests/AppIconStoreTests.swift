import AppKit
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class AppIconStoreTests: XCTestCase {
    private final class LoadCounter {
        var count = 0
    }

    func testFailedLoaderIsCalledOnceAcrossLookups() {
        let counter = LoadCounter()
        let store = AppIconStore { _ in
            counter.count += 1
            return nil
        }
        let application = ApplicationIdentity(name: "Missing", bundleID: "example.missing")

        XCTAssertNil(store.icon(for: application))
        XCTAssertNil(store.icon(for: application))
        XCTAssertEqual(counter.count, 1)
    }

    func testSuccessfulLoaderIsCalledOnceAcrossLookups() {
        let counter = LoadCounter()
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let store = AppIconStore { _ in
            counter.count += 1
            return image
        }
        let application = ApplicationIdentity(name: "Found", bundleID: "example.found")

        XCTAssertTrue(store.icon(for: application) === image)
        XCTAssertTrue(store.icon(for: application) === image)
        XCTAssertEqual(counter.count, 1)
    }

    func testBlankBundleIDNeverCallsLoader() {
        let counter = LoadCounter()
        let store = AppIconStore { _ in
            counter.count += 1
            return nil
        }

        XCTAssertNil(store.icon(for: ApplicationIdentity(name: "No bundle ID")))
        XCTAssertNil(store.icon(for: ApplicationIdentity(name: "Blank", bundleID: "   ")))
        XCTAssertEqual(counter.count, 0)
    }
}
