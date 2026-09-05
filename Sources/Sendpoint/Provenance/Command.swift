import Darwin
import Foundation

/// A subprocess belongs to the calling task. Nonblocking reads bound memory and
/// keep cancellation responsive, including when a child never closes stdout.
enum ProvenanceCommand {
    enum Failure: Error { case timedOut, outputTooLarge, exited(Int32), readFailed(Int32) }

    static func output(
        executable: URL, arguments: [String],
        timeout: Duration = .seconds(2), maximumBytes: Int = 1_048_576
    ) async throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let readHandle = pipe.fileHandleForReading
        let descriptor = readHandle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw Failure.readFailed(errno)
        }
        defer {
            // One teardown path covers success, cancellation, timeout and errors.
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            try? readHandle.close()
            try? pipe.fileHandleForWriting.close()
        }
        try process.run()
        try pipe.fileHandleForWriting.close()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.timedOut }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard output.count + count <= maximumBytes else { throw Failure.outputTooLarge }
                output.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                throw Failure.readFailed(errno)
            }
            if count == 0 && !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw Failure.exited(process.terminationStatus) }
        return output
    }
}
