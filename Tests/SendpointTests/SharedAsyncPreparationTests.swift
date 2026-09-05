import XCTest
@testable import Sendpoint

final class SharedAsyncPreparationTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    private actor CallCounter {
        private(set) var value = 0
        func increment() { value += 1 }
        func incrementAndGet() -> Int {
            value += 1
            return value
        }
    }

    func testConcurrentCallersShareOnePreparationTask() async throws {
        let preparation = SharedAsyncPreparation<Int>()
        let calls = CallCounter()
        let factory: @Sendable () async throws -> Int = {
            await calls.increment()
            try await Task.sleep(for: .milliseconds(40))
            return 42
        }

        async let first = preparation.value(prepare: factory)
        async let second = preparation.value(prepare: factory)
        async let third = preparation.value(prepare: factory)

        let values = try await [first, second, third]
        let initialCallCount = await calls.value
        let isPrepared = await preparation.isPrepared()
        let cachedValue = try await preparation.value(prepare: factory)
        let finalCallCount = await calls.value

        XCTAssertEqual(values, [42, 42, 42])
        XCTAssertEqual(initialCallCount, 1)
        XCTAssertTrue(isPrepared)
        XCTAssertEqual(cachedValue, 42)
        XCTAssertEqual(finalCallCount, 1)
    }

    func testFailedPreparationClearsInFlightStateAndLaterCallRetriesOnce() async throws {
        let preparation = SharedAsyncPreparation<Int>()
        let calls = CallCounter()
        let factory: @Sendable () async throws -> Int = {
            let attempt = await calls.incrementAndGet()
            if attempt == 1 { throw TestError.failed }
            return 42
        }

        do {
            _ = try await preparation.value(prepare: factory)
            XCTFail("The first preparation should fail")
        } catch TestError.failed {
            // Expected. A later caller must be able to start a new task.
        }

        let isPreparedAfterFailure = await preparation.isPrepared()
        let retriedValue = try await preparation.value(prepare: factory)
        let cachedValue = try await preparation.value(prepare: factory)
        let callCount = await calls.value

        XCTAssertFalse(isPreparedAfterFailure)
        XCTAssertEqual(retriedValue, 42)
        XCTAssertEqual(cachedValue, 42)
        XCTAssertEqual(callCount, 2)
    }
}
