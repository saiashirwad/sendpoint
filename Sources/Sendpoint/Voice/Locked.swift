import Foundation

nonisolated final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&stored)
    }

    var value: Value {
        get { withLock { $0 } }
        set { withLock { $0 = newValue } }
    }
}
