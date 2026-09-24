import Foundation

nonisolated enum StackSelectEvent: Equatable {
    case select(Int)
    case switchFailed(UUID)
    case readoutElapsed(generation: Int)
    case teardown
}

nonisolated enum StackSelectEffect: Equatable {
    case switchTo(UUID)
    case showReadout(number: Int)
    case hideReadout
    case startTimer(generation: Int)
    case beep
}

nonisolated struct StackSelectMachine: Equatable {
    enum State: Equatable {
        case idle
        case showing(UUID, generation: Int)
        case tornDown
    }

    private(set) var state: State = .idle
    private var generation = 0

    mutating func update(
        _ event: StackSelectEvent, stacks: [UUID], showsReadout: Bool
    ) -> [StackSelectEffect] {
        guard state != .tornDown else { return [] }
        switch event {
        case .teardown:
            let wasShowing = isShowing
            state = .tornDown
            return wasShowing ? [.hideReadout] : []

        case let .select(number):
            guard stacks.indices.contains(number - 1) else { return [.beep] }
            let id = stacks[number - 1]
            var effects: [StackSelectEffect] = [.switchTo(id)]
            if showsReadout {
                generation += 1
                state = .showing(id, generation: generation)
                effects += [.showReadout(number: number), .startTimer(generation: generation)]
            } else if isShowing {
                state = .idle
                effects.append(.hideReadout)
            }
            return effects

        case let .switchFailed(id):
            guard case .showing(id, _) = state else { return [.beep] }
            state = .idle
            return [.hideReadout, .beep]

        case let .readoutElapsed(elapsed):
            guard case .showing(_, elapsed) = state else { return [] }
            state = .idle
            return [.hideReadout]
        }
    }

    private var isShowing: Bool {
        if case .showing = state { return true }
        return false
    }
}
