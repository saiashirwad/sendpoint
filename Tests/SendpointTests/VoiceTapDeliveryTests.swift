import XCTest
@testable import Sendpoint

@MainActor
final class VoiceTapDeliveryTests: XCTestCase {
    func testLevelsYieldedBeforeStopAreNotDeliveredAfterIt() async {
        let pump = LatestValuePump<Float>()
        var delivered: [Float] = []
        let continuation = pump.start { delivered.append($0) }

        continuation.yield(0.5)
        for _ in 0..<2000 where delivered.isEmpty { await Task.yield() }
        XCTAssertEqual(delivered, [0.5])

        continuation.yield(1.0)
        pump.stop()
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(delivered, [0.5], "a late flush from a stopped tap must not reach the meter")
    }

    func testRestartingCutsOffThePreviousTap() async {
        let pump = LatestValuePump<Float>()
        var delivered: [String] = []
        let first = pump.start { _ in delivered.append("first") }
        let second = pump.start { _ in delivered.append("second") }

        first.yield(1.0)
        second.yield(1.0)
        for _ in 0..<2000 where delivered.isEmpty { await Task.yield() }
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(delivered, ["second"])
    }
}
