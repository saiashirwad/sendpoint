import AppKit
import SendpointDomain

@MainActor
final class StackSelector {
    static let readoutDuration: Duration = .milliseconds(700)

    private let store: StackStore
    private let showsReadout: () -> Bool
    private let showReadout: (Int) -> Void
    private let hideReadout: () -> Void
    private let onSelected: (UUID) -> Void
    private let sleep: @MainActor (Duration) async throws -> Void
    private var machine = StackSelectMachine()
    private var timer: Task<Void, Never>?

    init(store: StackStore,
         showsReadout: @escaping () -> Bool,
         showReadout: @escaping (Int) -> Void,
         hideReadout: @escaping () -> Void,
         onSelected: @escaping (UUID) -> Void,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.showsReadout = showsReadout
        self.showReadout = showReadout
        self.hideReadout = hideReadout
        self.onSelected = onSelected
        self.sleep = sleep
    }

    func select(_ number: Int) { send(.select(number)) }

    func teardown() {
        send(.teardown)
        timer?.cancel()
        timer = nil
    }

    private func send(_ event: StackSelectEvent) {
        let commands = machine.handle(event, stacks: store.stacks.map(\.id), showsReadout: showsReadout())
        for command in commands { run(command) }
    }

    private func run(_ command: StackSelectCommand) {
        switch command {
        case let .switchTo(id):
            onSelected(id)
            store.mutate(.switchStack(stackID: id)) { [weak self] outcome in
                switch outcome {
                case .committed, .noOp: break
                case .rejected, .commitFailed, .cancelled: self?.send(.switchFailed(id))
                }
            }
        case let .showReadout(number):
            showReadout(number)
        case .hideReadout:
            timer?.cancel()
            timer = nil
            hideReadout()
        case let .startTimer(generation):
            timer?.cancel()
            timer = Task { @MainActor [weak self, sleep] in
                do { try await sleep(Self.readoutDuration) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.timer = nil
                self.send(.readoutElapsed(generation: generation))
            }
        case .beep:
            NSSound.beep()
        }
    }
}
