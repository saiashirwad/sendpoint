import Foundation

final class TapLevelPump {
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<Float>.Continuation?

    func start(deliver: @escaping (Float) -> Void) -> AsyncStream<Float>.Continuation {
        stop()
        let (levels, continuation) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        task = Task {
            for await level in levels {
                guard !Task.isCancelled else { return }
                deliver(level)
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
