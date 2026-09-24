import XCTest
@testable import Sendpoint

@MainActor
final class NoteFramesDisarmTests: XCTestCase {
    func testDisarmClearsLandingSoSettleNoOps() {
        let frames = NoteFrames()
        let id = UUID()
        frames.frames[id] = CGRect(x: 0, y: 0, width: 100, height: 100)

        frames.land(on: id)
        XCTAssertEqual(frames.landing, id)

        frames.disarm()
        XCTAssertNil(frames.landing)

        frames.settle()
        XCTAssertNil(frames.landing)
        XCTAssertEqual(frames.frames[id], CGRect(x: 0, y: 0, width: 100, height: 100), "disarm clears the landing, never the frames")
    }

    func testDisarmIsIdempotent() {
        let frames = NoteFrames()
        frames.disarm()
        frames.disarm()
        XCTAssertNil(frames.landing)
    }

    func testLateSettleRetryAfterDisarmNoOps() async {
        let frames = NoteFrames()
        let id = UUID()
        frames.frames[id] = CGRect(x: 0, y: 400, width: 100, height: 100)

        frames.land(on: id)
        frames.disarm()

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(frames.landing)
    }
}
