import SendpointDomain
import Foundation

/// Retains probe work after a successful save, but not after an unsaved cancel.
final class PendingProvenanceWorkOwner {
    typealias LateUpdate = @MainActor (StackDocumentMutation) -> Void

    private struct Route: Equatable, Sendable {
        let captureID: UUID
        let noteID: UUID
        let stackID: UUID
        let application: ApplicationIdentity

        init(target: NoteCaptureTarget) {
            captureID = target.captureID
            noteID = target.noteID
            stackID = target.stackID
            application = target.application
        }
    }

    private struct Work {
        let route: Route
        var task: Task<Void, Never>?
        var provenance: Provenance?
        var savedNote: Note?
    }

    private let probe: ProvenanceProbe
    private let lateUpdate: LateUpdate
    private var workByCaptureID: [UUID: Work] = [:]
    private var activeTaskCaptureIDs: Set<UUID> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isTornDown = false

    init(probe: ProvenanceProbe, lateUpdate: @escaping LateUpdate) {
        self.probe = probe
        self.lateUpdate = lateUpdate
    }

    var pendingCount: Int { workByCaptureID.count }
    var pendingTaskCount: Int { activeTaskCaptureIDs.count }

    func waitForIdle() async {
        guard pendingTaskCount > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    func start(for target: NoteCaptureTarget) {
        guard !isTornDown,
              workByCaptureID[target.captureID] == nil,
              !activeTaskCaptureIDs.contains(target.captureID)
        else { return }
        let route = Route(target: target)
        let application = CapturedApplication(
            identity: target.application,
            processIdentifier: target.captured.processIdentifier
        )
        workByCaptureID[route.captureID] = Work(
            route: route,
            task: nil,
            provenance: nil,
            savedNote: nil
        )
        activeTaskCaptureIDs.insert(route.captureID)

        let task = Task { [weak self, probe] in
            let provenance = await probe.probe(application)
            if !Task.isCancelled {
                self?.probeFinished(provenance, route: route)
            }
            self?.probeTaskFinished(captureID: route.captureID)
        }
        workByCaptureID[route.captureID]?.task = task
    }

    /// Marks the capture saved and returns the best provenance available now.
    /// If work is still pending, the retained task will send one exact late update.
    func noteForSave(
        _ note: Note,
        target: NoteCaptureTarget
    ) -> Note {
        guard !isTornDown,
              var work = workByCaptureID[target.captureID],
              work.route == Route(target: target),
              note.id == target.noteID,
              note.provenance.application == target.application
        else { return note }

        if let provenance = work.provenance,
           provenance.application == target.application {
            var enriched = note
            enriched.provenance = provenance
            work.task?.cancel()
            workByCaptureID.removeValue(forKey: target.captureID)
            return enriched
        }

        work.savedNote = note
        workByCaptureID[target.captureID] = work
        return note
    }

    /// Cancels matching work, even after it was prepared for a save: the save
    /// was rejected, the user chose a new destination, or the capture was dropped.
    func abandon(for target: NoteCaptureTarget) {
        guard let work = workByCaptureID[target.captureID],
              work.route == Route(target: target)
        else { return }
        work.task?.cancel()
        workByCaptureID.removeValue(forKey: target.captureID)
        resumeIdleWaitersIfNeeded()
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        let work = workByCaptureID.values
        workByCaptureID.removeAll()
        activeTaskCaptureIDs.removeAll()
        work.forEach { $0.task?.cancel() }
        resumeIdleWaitersIfNeeded()
    }

    private func probeFinished(_ provenance: Provenance, route: Route) {
        guard !isTornDown,
              var work = workByCaptureID[route.captureID],
              work.route == route
        else { return }
        work.task = nil

        guard provenance.application == route.application else {
            workByCaptureID.removeValue(forKey: route.captureID)
            return
        }

        guard let saved = work.savedNote else {
            work.provenance = provenance
            workByCaptureID[route.captureID] = work
            return
        }
        guard saved.id == route.noteID,
              saved.provenance.application == route.application
        else {
            workByCaptureID.removeValue(forKey: route.captureID)
            return
        }

        workByCaptureID.removeValue(forKey: route.captureID)
        lateUpdate(.updateNoteProvenance(
            stackID: route.stackID,
            noteID: route.noteID,
            expectedApplication: route.application,
            provenance: provenance
        ))
    }

    private func probeTaskFinished(captureID: UUID) {
        activeTaskCaptureIDs.remove(captureID)
        resumeIdleWaitersIfNeeded()
    }

    private func resumeIdleWaitersIfNeeded() {
        guard pendingTaskCount == 0 else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
