import SendpointDomain
import Foundation

nonisolated struct NoteCaptureContext: Equatable {
    let stackID: UUID
    let noteID: UUID
    let createdAt: Date

    init(stackID: UUID, noteID: UUID = UUID(), createdAt: Date = Date()) {
        self.stackID = stackID
        self.noteID = noteID
        self.createdAt = createdAt
    }

    func target(captured: CapturedSelection) -> NoteCaptureTarget {
        NoteCaptureTarget(context: self, captured: captured)
    }
}

nonisolated struct NoteCaptureTarget: Equatable {
    let context: NoteCaptureContext
    let captured: CapturedSelection

    init(context: NoteCaptureContext, captured: CapturedSelection) {
        self.context = context
        self.captured = captured
    }

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
