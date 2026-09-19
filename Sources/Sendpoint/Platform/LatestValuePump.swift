import Foundation

final class LatestValuePump<Value: Sendable> {
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<Value>.Continuation?

    func start(deliver: @escaping (Value) -> Void) -> AsyncStream<Value>.Continuation {
        stop()
        let (values, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        task = Task {
            for await value in values {
                guard !Task.isCancelled else { return }
                deliver(value)
            }
        }
        return continuation
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }
}
