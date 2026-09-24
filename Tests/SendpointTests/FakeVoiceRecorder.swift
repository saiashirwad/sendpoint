import Foundation
import SendpointDomain
@testable import Sendpoint

@MainActor
final class FakeVoiceRecorder {
    actor StartGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open(_ value: Bool) {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    var starts = 0
    var discards = 0
    var startFails = false
    var transcript: Result<String, Error> = .success("hello there")
    let started = StartGate()
    private(set) var takes: [UUID] = []
    private var output: ((VoiceOutput) -> Void)?

    var partialHandlers: [(String) -> Void] {
        takes.map { take in { [weak self] in self?.output?(.partial(take, $0)) } }
    }
    var partialHandler: ((String) -> Void)? { partialHandlers.last }

    var boundary: VoiceRecorder {
        VoiceRecorder(
            start: { take in
                self.starts += 1
                self.takes.append(take)
                if self.startFails {
                    self.output?(.failed(take, "mic busy"))
                    return
                }
                Task {
                    await self.started.wait()
                    self.output?(.started(take))
                }
            },
            stop: { take in
                switch self.transcript {
                case let .success(text): self.output?(.transcript(take, text))
                case let .failure(error): self.output?(.failed(take, error.localizedDescription))
                }
            },
            discard: { self.discards += 1 },
            levelMeter: VoiceLevelMeter(),
            observe: { self.output = $0 }
        )
    }
}
