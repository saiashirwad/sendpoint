import AppKit
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class AppIconStoreTests: XCTestCase {
    func testLoaderRunsOncePerBundleIDAndNeverForABlankOne() {
        var loads: [String] = []
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let store = AppIconStore { bundleID in
            loads.append(bundleID)
            return bundleID == "example.found" ? image : nil
        }
        let found = ApplicationIdentity(name: "Found", bundleID: "example.found")
        let missing = ApplicationIdentity(name: "Missing", bundleID: "example.missing")

        XCTAssertTrue(store.icon(for: found) === image)
        XCTAssertTrue(store.icon(for: found) === image)
        XCTAssertNil(store.icon(for: missing))
        XCTAssertNil(store.icon(for: missing), "a failed load is remembered too")
        XCTAssertNil(store.icon(for: ApplicationIdentity(name: "No bundle ID")))
        XCTAssertNil(store.icon(for: ApplicationIdentity(name: "Blank", bundleID: "   ")))
        XCTAssertEqual(loads, ["example.found", "example.missing"])
    }
}
