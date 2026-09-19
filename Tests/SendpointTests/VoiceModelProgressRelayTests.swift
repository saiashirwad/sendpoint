import XCTest
@testable import Sendpoint

final class VoiceModelProgressRelayTests: XCTestCase {
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        var received: [Double] { lock.withLock { values } }
        func handler() -> @Sendable (Double) -> Void {
            { [self] value in lock.withLock { values.append(value) } }
        }
    }

    func testLateSubscriberGetsTheLatestFractionAtOnce() {
        let relay = VoiceModelProgressRelay()
        relay.report(0.25)
        relay.report(0.4)

        let late = Sink()
        relay.subscribe(late.handler())
        XCTAssertEqual(late.received, [0.4])

        relay.report(0.6)
        XCTAssertEqual(late.received, [0.4, 0.6])
    }

    func testEveryObserverHearsEveryReportUntilItUnsubscribes() {
        let relay = VoiceModelProgressRelay()
        let first = Sink(), second = Sink()
        let firstToken = relay.subscribe(first.handler())
        relay.subscribe(second.handler())

        relay.report(0.1)
        relay.unsubscribe(firstToken)
        relay.report(0.2)

        XCTAssertEqual(first.received, [0.1])
        XCTAssertEqual(second.received, [0.1, 0.2])
    }

    func testResetStopsAStaleFractionReplayingIntoTheNextAttempt() {
        let relay = VoiceModelProgressRelay()
        relay.report(0.9)
        relay.reset()

        let sink = Sink()
        relay.subscribe(sink.handler())
        XCTAssertEqual(sink.received, [])
    }
}
