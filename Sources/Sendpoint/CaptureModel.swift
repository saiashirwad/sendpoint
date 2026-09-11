import SendpointDomain
import Foundation

/// IDs and time captured before selection reading or recording can delay us.
nonisolated struct NoteCaptureContext: Equatable {
    let captureID: UUID
    let stackID: UUID
    let noteID: UUID
    let createdAt: Date

    init(stackID: UUID, captureID: UUID = UUID(), noteID: UUID = UUID(), createdAt: Date = Date()) {
        self.captureID = captureID
        self.stackID = stackID
        self.noteID = noteID
        self.createdAt = createdAt
    }

    func target(captured: CapturedSelection) -> NoteCaptureTarget {
        NoteCaptureTarget(context: self, captured: captured)
    }
}

/// Immutable values captured when a panel starts. Delayed saves must use this
/// target instead of whichever stack is current later.
nonisolated struct NoteCaptureTarget: Equatable {
    let context: NoteCaptureContext
    let captured: CapturedSelection

    init(context: NoteCaptureContext, captured: CapturedSelection) {
        self.context = context
        self.captured = captured
    }

    var captureID: UUID { context.captureID }
    var stackID: UUID { context.stackID }
    var noteID: UUID { context.noteID }
    var createdAt: Date { context.createdAt }

    func note(body: String) -> Note? {
        Note.capturing(
            selection: captured.text,
            body: body,
            id: noteID,
            createdAt: createdAt
        )
    }
}
