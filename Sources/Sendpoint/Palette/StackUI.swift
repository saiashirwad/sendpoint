import SendpointDomain
import Foundation
import SwiftUI

nonisolated func noteCountLabel(_ count: Int) -> String {
    "\(count) note\(count == 1 ? "" : "s")"
}

nonisolated func noteTimestampLabel(
    _ date: Date, now: Date = Date(), calendar: Calendar = .current
) -> String {
    let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(style.hour().minute())
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
        return date.formatted(style.day().month(.abbreviated))
    }
    return date.formatted(style.day().month(.abbreviated).year())
}

nonisolated func stackStatusDetail(
    noteCount: Int, latest: Date?, now: Date = Date(), calendar: Calendar = .current
) -> String {
    guard noteCount > 0, let latest else { return "Nothing captured yet" }
    return "\(noteCountLabel(noteCount)) · \(noteTimestampLabel(latest, now: now, calendar: calendar))"
}

nonisolated func noteRevealAnchor(frame: CGRect, viewportHeight: CGFloat) -> UnitPoint? {
    if frame.minY < 0 { return .top }
    if frame.maxY > viewportHeight { return .bottom }
    return nil
}

nonisolated func revealedScrollOffset(
    currentTop: CGFloat, frame: CGRect, viewportHeight: CGFloat, contentHeight: CGFloat,
    anchor: UnitPoint, margin: CGFloat = 6
) -> CGFloat {
    let wanted: CGFloat = anchor == .top
        ? currentTop + frame.minY - margin
        : currentTop + frame.maxY + margin - viewportHeight
    return min(max(wanted, 0), max(0, contentHeight - viewportHeight))
}

nonisolated func wrappedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
    ((index + offset) % count + count) % count
}

nonisolated func stackTitle(_ number: Int) -> String {
    "Stack \(number)"
}

nonisolated struct StackItemFacts: Equatable, Identifiable {
    let id: UUID
    let number: Int
    let noteCount: Int
    let isCurrent: Bool
    let startedAt: Date?

    var name: String { stackTitle(number) }
    var countLabel: String { noteCountLabel(noteCount) }
    var isEmpty: Bool { noteCount == 0 }
}

nonisolated struct StackUndoFacts: Equatable {
    let stackID: UUID
    let stackName: String
    let noteCount: Int
    let isCurrentStack: Bool

    var notification: String {
        "Cleared \(noteCountLabel(noteCount)) in \(stackName)"
    }

    var title: String {
        let count = "\(noteCount)"
        return isCurrentStack
            ? "Undo Clear (\(count))"
            : "Undo Clear in \(stackName) (\(count))"
    }
}

nonisolated struct StackUIFacts: Equatable {
    let stacks: [StackItemFacts]
    let currentStackID: UUID
    let undo: StackUndoFacts?

    @MainActor init(store: StackStore) {
        self.init(stacks: store.stacks, currentStackID: store.currentStackID, lastCleared: store.lastCleared)
    }

    init(stacks: [Stack], currentStackID: UUID, lastCleared: ClearedBatch?) {
        self.stacks = stacks.enumerated().map { index, stack in
            StackItemFacts(
                id: stack.id,
                number: index + 1,
                noteCount: stack.notes.count,
                isCurrent: stack.id == currentStackID,
                startedAt: stack.startedAt
            )
        }
        self.currentStackID = currentStackID

        if let lastCleared, let number = stacks.number(of: lastCleared.stackID) {
            undo = StackUndoFacts(
                stackID: lastCleared.stackID,
                stackName: stackTitle(number),
                noteCount: lastCleared.notes.count,
                isCurrentStack: lastCleared.stackID == currentStackID
            )
        } else {
            undo = nil
        }
    }

    var current: StackItemFacts? {
        stacks.first(where: { $0.id == currentStackID })
    }

    func stack(id: UUID) -> StackItemFacts? {
        stacks.first(where: { $0.id == id })
    }

    func stack(number: Int) -> StackItemFacts? {
        stacks.first(where: { $0.number == number })
    }
}

func noteStoreErrorMessage(_ error: StackStoreError) -> String {
    switch error {
    case let .mutationRejected(message):
        return message
    case let .commitFailed(message):
        return "Couldn't save the stack change: \(message)"
    case .tornDown:
        return "Stack storage is no longer available."
    }
}
