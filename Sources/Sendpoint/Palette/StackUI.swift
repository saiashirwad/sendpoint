import SendpointDomain
import Foundation
import SwiftUI

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
