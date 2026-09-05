import SendpointDomain
import Foundation

/// IDs and time captured before selection reading or recording can delay us.
struct AnnotationCaptureContext: Equatable {
    let captureID: UUID
    let sessionID: UUID
    let annotationID: UUID
    let createdAt: Date

    init(sessionID: UUID, captureID: UUID = UUID(), annotationID: UUID = UUID(), createdAt: Date = Date()) {
        self.captureID = captureID
        self.sessionID = sessionID
        self.annotationID = annotationID
        self.createdAt = createdAt
    }

    func target(captured: CapturedSelection) -> AnnotationCaptureTarget {
        AnnotationCaptureTarget(context: self, captured: captured)
    }
}

/// Immutable values captured when a panel starts. Delayed saves must use this
/// target instead of whichever session or application is current later.
struct AnnotationCaptureTarget: Equatable {
    let context: AnnotationCaptureContext
    let captured: CapturedSelection
    let application: ApplicationIdentity

    init(context: AnnotationCaptureContext, captured: CapturedSelection) {
        self.context = context
        self.captured = captured
        application = ApplicationIdentity(
            name: captured.appName?.nonblank ?? "Unknown Application",
            bundleID: captured.appBundleID
        )
    }

    var captureID: UUID { context.captureID }
    var sessionID: UUID { context.sessionID }
    var annotationID: UUID { context.annotationID }
    var createdAt: Date { context.createdAt }
}

/// Applies the note policy at the boundary between capture UI and the store.
enum CaptureAnnotationPolicy {
    static func annotation(for target: AnnotationCaptureTarget, note: String) -> Annotation? {
        guard let note = note.nonblank else { return nil }
        return Annotation(
            id: target.annotationID,
            subject: target.captured.text.nonblank == nil ? .standalone : .selection(quote: target.captured.text),
            note: note,
            provenance: Provenance(application: target.application),
            createdAt: target.createdAt
        )
    }
}
