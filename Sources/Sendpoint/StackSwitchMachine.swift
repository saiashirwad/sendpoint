import Foundation

/// What the switcher walks. The strip always shows the listed order, so each
/// stack keeps its row and can be recognised by place. Recency decides only
/// where a cycle starts: the first press lights the stack used just before
/// this one, wherever it sits; further presses move down the fixed list.
nonisolated struct StackSwitchOrders: Equatable {
    var recent: [UUID]
    var listed: [UUID]
}

nonisolated enum StackSwitchEvent: Equatable {
    /// The switch shortcut, or its ⇧ variant when `reverse` is set.
    case press(reverse: Bool)
    /// Every modifier of the switch shortcut is up.
    case release
    case escape
    /// An arrow key while cycling: hand the choice to the full palette.
    case pin
    /// A direct next or previous key, outside of any hold.
    case step(Int)
    case ordersChanged
    /// The confirmation has been on screen long enough.
    case lingerElapsed
    case teardown
}

nonisolated enum StackSwitchCommand: Equatable {
    case showOverlay
    case hideOverlay
    case switchTo(UUID)
    case openPalette(highlighting: UUID)
    case startLinger
    case beep
}

/// ⌘Tab for stacks, as a pure transition table. The owner supplies the
/// current orders with each event and runs the returned commands; the
/// machine holds the frozen list the overlay draws and which row is lit.
nonisolated struct StackSwitchMachine: Equatable {
    enum State: Equatable {
        case idle
        /// Modifiers held; each press moves the highlight.
        case cycling
        /// A switch was committed and the overlay shows the result briefly.
        case lingering
        case tornDown
    }

    private(set) var state: State = .idle
    /// The stacks the overlay lists, in the fixed listed order.
    private(set) var order: [UUID] = []
    private(set) var highlight: UUID?

    var isShowingOverlay: Bool { state == .cycling || state == .lingering }

    mutating func handle(_ event: StackSwitchEvent, orders: StackSwitchOrders) -> [StackSwitchCommand] {
        guard state != .tornDown else { return [] }
        switch event {
        case .teardown:
            state = .tornDown
            order = []
            highlight = nil
            return [.hideOverlay]

        case let .press(reverse):
            switch state {
            case .idle, .lingering:
                guard orders.listed.count > 1, orders.recent.count > 1,
                      let current = orders.listed.firstIndex(of: orders.recent[0])
                else { return finish(with: [.beep]) }
                let wasLingering = state == .lingering
                order = orders.listed
                // Forward starts at the stack used last; backwards starts one
                // row above the current one, so ⇧ reads as "up" on the strip.
                if reverse {
                    highlight = order[(current - 1 + order.count) % order.count]
                } else {
                    highlight = orders.recent[1]
                }
                state = .cycling
                return wasLingering ? [] : [.showOverlay]
            case .cycling:
                move(by: reverse ? -1 : 1)
                return []
            case .tornDown:
                return []
            }

        case .release:
            guard state == .cycling, let highlight else { return [] }
            state = .lingering
            return [.switchTo(highlight), .startLinger]

        case .escape:
            guard state == .cycling else { return [] }
            return finish(with: [.hideOverlay])

        case .pin:
            guard state == .cycling, let highlight else { return [] }
            return finish(with: [.hideOverlay, .openPalette(highlighting: highlight)])

        case let .step(offset):
            guard state != .cycling else { return [] }
            let listed = orders.listed
            guard listed.count > 1, let current = orders.recent.first,
                  let index = listed.firstIndex(of: current)
            else { return finish(with: [.beep]) }
            let target = listed[wrappedIndex(index, by: offset, count: listed.count)]
            let wasVisible = state == .lingering
            order = listed
            highlight = target
            state = .lingering
            return (wasVisible ? [] : [.showOverlay]) + [.switchTo(target), .startLinger]

        case .ordersChanged:
            guard state == .cycling else { return [] }
            guard orders.listed.count > 1 else { return finish(with: [.hideOverlay]) }
            let previousIndex = highlight.flatMap { order.firstIndex(of: $0) } ?? 0
            order = orders.listed
            if let highlight, order.contains(highlight) { return [] }
            highlight = order[min(previousIndex, order.count - 1)]
            return []

        case .lingerElapsed:
            guard state == .lingering else { return [] }
            return finish(with: [.hideOverlay])
        }
    }

    private mutating func move(by offset: Int) {
        guard !order.isEmpty else { return }
        let index = highlight.flatMap { order.firstIndex(of: $0) } ?? 0
        highlight = order[wrappedIndex(index, by: offset, count: order.count)]
    }

    private mutating func finish(with commands: [StackSwitchCommand]) -> [StackSwitchCommand] {
        state = .idle
        order = []
        highlight = nil
        return commands
    }
}
