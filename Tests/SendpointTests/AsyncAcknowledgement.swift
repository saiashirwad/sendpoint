import Foundation
import Observation
import XCTest

@MainActor
final class AsyncAcknowledgement {
    private(set) var count = 0
    private var waiters: [(Int, XCTestExpectation)] = []

    func signal() {
        count += 1
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.fulfill() }
    }

    func wait(for count: Int = 1, file: StaticString = #filePath, line: UInt = #line) async {
        guard self.count < count else { return }
        let expectation = XCTestExpectation(description: "Acknowledgment \(count)")
        waiters.append((count, expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        waiters.removeAll { $0.1 === expectation }
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
}

@MainActor
final class ControlledSleep {
    let started = AsyncAcknowledgement()
    let completed = AsyncAcknowledgement()
    private(set) var durations: [Duration] = []
    private var pending: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        defer { completed.signal() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                durations.append(duration)
                pending[id] = (duration, continuation)
                started.signal()
            }
        } onCancel: {
            Task { @MainActor in
                self.pending.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
    }

    func advance(_ duration: Duration) {
        let ready = pending.filter { $0.value.0 == duration }
        for (id, value) in ready {
            pending.removeValue(forKey: id)
            value.1.resume()
        }
    }
}

@MainActor
private final class ObservedCondition {
    let expectation = XCTestExpectation(description: "Observed condition")
    let condition: @MainActor () -> Bool
    var active = true

    init(_ condition: @escaping @MainActor () -> Bool) { self.condition = condition }

    func observe() {
        guard active else { return }
        let matched = withObservationTracking { condition() } onChange: {
            Task { @MainActor in self.observe() }
        }
        if matched {
            active = false
            expectation.fulfill()
        }
    }
}

@MainActor
func waitForObservation(_ condition: @escaping @MainActor () -> Bool,
                        file: StaticString = #filePath, line: UInt = #line) async {
    let observed = ObservedCondition(condition)
    observed.observe()
    let result = await XCTWaiter.fulfillment(of: [observed.expectation], timeout: 5)
    observed.active = false
    XCTAssertEqual(result, .completed, file: file, line: line)
}
