import Darwin
import Foundation
import XCTest
@testable import Sendpoint

final class ProvenanceCommandTests: XCTestCase {
    func testArgumentsArePassedLiterallyAndNonzeroExitFails() async throws {
        let literal = "spaces ; $(echo bad) `echo bad`\nquotes\""
        let result = try await ProvenanceCommand.output(
            executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", literal]
        )
        XCTAssertEqual(String(decoding: result, as: UTF8.self), literal)
        do {
            _ = try await ProvenanceCommand.output(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
            XCTFail("Expected failure")
        } catch ProvenanceCommand.Failure.exited(let status) {
            XCTAssertNotEqual(status, 0)
        }
    }

    func testTimeoutAndOutputLimitStopCommands() async throws {
        do {
            _ = try await ProvenanceCommand.output(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(30)
            )
            XCTFail("Expected timeout")
        } catch ProvenanceCommand.Failure.timedOut { }
        do {
            _ = try await ProvenanceCommand.output(
                executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], maximumBytes: 100
            )
            XCTFail("Expected output limit")
        } catch ProvenanceCommand.Failure.outputTooLarge { }
    }

    func testCancellationReapsOwnedSubprocess() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let task = Task {
            try await ProvenanceCommand.output(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", #"echo $$ > "$1"; exec /bin/sleep 30"#, "provenance-test", marker.path],
                timeout: .seconds(5)
            )
        }
        // The marker establishes that the child is running before cancellation.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var pid: pid_t?
        while ContinuousClock.now < deadline {
            if let text = try? String(contentsOf: marker),
               let value = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pid = value
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let childPID = try XCTUnwrap(pid, "Child did not start")
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }
}
