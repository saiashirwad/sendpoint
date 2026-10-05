import AppKit
import Observation
import SendpointDomain

struct ExportRequest: Equatable {
    let id: UUID
    let stack: Stack
    let markdown: String
    let clearAfterCopy: Bool
    let pasteTarget: pid_t?
}

enum ExportEvent {
    case begin(ExportRequest)
    case copied(UUID, revision: Int?)
    case pasted(UUID, dispatched: Bool)
    case cleared(UUID, StackMutationOutcome)
    case retry, teardown
}

enum ExportEffect {
    case write(ExportRequest)
    case paste(ExportRequest, revision: Int)
    case clear(ExportRequest)
    case report(String)
    case retry, cancelPaste
}

enum ExportState: Equatable {
    case idle
    case copying(ExportRequest)
    case awaitingPaste(ExportRequest, revision: Int)
    case clearing(ExportRequest)
    case failed(ExportRequest, String, retryable: Bool)
    case tornDown

    mutating func update(_ event: ExportEvent) -> [ExportEffect] {
        guard self != .tornDown else { return [] }
        switch event {
        case .teardown: self = .tornDown; return [.cancelPaste]
        case let .begin(request):
            switch self {
            case .clearing, .failed(_, _, true): return [.report("Finish or retry the pending export first.")]
            default: break
            }
            self = .copying(request)
            return [.cancelPaste, .write(request)]
        case let .copied(id, revision):
            guard case let .copying(request) = self, request.id == id else { return [] }
            guard let revision else { return fail(request, "Couldn’t copy the notes.") }
            if request.pasteTarget != nil {
                self = .awaitingPaste(request, revision: revision)
                return [.paste(request, revision: revision)]
            }
            return finishCopy(request)
        case let .pasted(id, dispatched):
            guard case let .awaitingPaste(request, _) = self, request.id == id else { return [] }
            guard dispatched else { return fail(request, "Clipboard changed; paste was cancelled. Notes were kept.") }
            return finishCopy(request)
        case let .cleared(id, outcome):
            let request: ExportRequest
            switch self {
            case let .clearing(value), let .failed(value, _, true): request = value
            default: return []
            }
            guard request.id == id else { return [] }
            switch outcome {
            case .committed, .noOp: self = .idle; return []
            case let .commitFailed(message): return fail(request, message, retryable: true)
            case let .rejected(message): return fail(request, message)
            case .cancelled: return fail(request, "Export cleanup was cancelled.")
            }
        case .retry:
            guard case let .failed(request, _, true) = self else { return [] }
            self = .clearing(request)
            return [.retry]
        }
    }

    private mutating func finishCopy(_ request: ExportRequest) -> [ExportEffect] {
        let verb = request.pasteTarget == nil ? "Copied" : "Paste sent for"
        let report = ExportEffect.report("\(verb) \(noteCountLabel(request.stack.notes.count))")
        self = request.clearAfterCopy ? .clearing(request) : .idle
        return request.clearAfterCopy ? [report, .clear(request)] : [report]
    }
    private mutating func fail(_ request: ExportRequest, _ message: String, retryable: Bool = false) -> [ExportEffect] {
        self = .failed(request, message, retryable: retryable)
        return [.report(message)]
    }
}
struct ExportServices {
    var write: (String) -> Int?
    var paste: (pid_t, Int) async throws -> Bool

    static func live(selection: SelectionCapture) -> Self {
        Self(write: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string) ? pasteboard.changeCount : nil
        }, paste: { pid, revision in
            try await Task.sleep(for: .milliseconds(120))
            return try await selection.paste(pid, revision)
        })
    }
}
@Observable
final class ExportController {
    private(set) var state: ExportState = .idle
    @ObservationIgnored private let services: ExportServices
    @ObservationIgnored private(set) var pasteTask: (requestID: UUID, task: Task<Void, Never>)?
    private struct Context {
        let requestID: UUID
        weak var store: StackStore?
        let report: (String) -> Void
    }
    private struct Pending {
        let event: ExportEvent
        let proposed: Context?
    }
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private let diagnostics: DiagnosticSink
    @ObservationIgnored private var pending: [Pending] = []
    @ObservationIgnored private var isDraining = false

    init(services: ExportServices, diagnostics: @escaping DiagnosticSink = Diag.record) {
        self.services = services
        self.diagnostics = diagnostics
    }

    func copy(store: StackStore, stackID: UUID, template: Template,
              pasteTarget: pid_t? = nil, report: @escaping (String) -> Void) {
        guard let stack = store.stack(id: stackID), !stack.notes.isEmpty else {
            report("Nothing to copy")
            return
        }
        let request = ExportRequest(id: UUID(), stack: stack,
            markdown: PromptComposer.markdown(stack: stack, template: template),
            clearAfterCopy: template.clearStackAfterExport, pasteTarget: pasteTarget)
        enqueue(.begin(request), proposed: Context(requestID: request.id, store: store, report: report))
    }

    func copyNote(_ note: Note, report: (String) -> Void) {
        guard state != .tornDown else { return }
        cancelPaste()
        if case let .awaitingPaste(request, _) = state { send(.pasted(request.id, dispatched: false)) }
        guard state != .tornDown else { return }
        let revision = services.write(PromptComposer.noteMarkdown(note))
        diagnostics(DiagnosticRecord(.clipboard, revision == nil ? .failed : .succeeded, operationID: UUID(), noteID: note.id))
        report(revision == nil ? "Couldn’t copy the note." : "Copied note")
    }

    func send(_ event: ExportEvent) {
        enqueue(event)
    }

    private func enqueue(_ event: ExportEvent, proposed: Context? = nil) {
        pending.append(Pending(event: event, proposed: proposed))
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let previous = state
            let effects = state.update(next.event)
            if case let .cleared(id, outcome) = next.event,
               context?.requestID == id, previous != state {
                diagnostics(DiagnosticRecord(.cleanup, outcome.diagnosticOutcome, operationID: id))
            }
            if let proposed = next.proposed {
                if case let .copying(request) = state, request.id == proposed.requestID {
                    context = proposed
                    diagnostics(DiagnosticRecord(.export, .accepted, operationID: request.id, stackID: request.stack.id))
                    for note in request.stack.notes {
                        diagnostics(DiagnosticRecord(.export, .accepted, operationID: request.id,
                                                     stackID: request.stack.id, noteID: note.id))
                    }
                } else {
                    diagnostics(DiagnosticRecord(.export, .rejected, operationID: proposed.requestID))
                    for effect in effects {
                        if case let .report(message) = effect { proposed.report(message) }
                    }
                    continue
                }
            }
            run(effects)
            if state == .idle || state == .tornDown { context = nil }
        }
        isDraining = false
    }

    private func run(_ effects: [ExportEffect]) {
        for effect in effects {
            switch effect {
            case let .write(request):
                let revision = services.write(request.markdown)
                diagnostics(DiagnosticRecord(.clipboard, revision == nil ? .failed : .succeeded, operationID: request.id))
                send(.copied(request.id, revision: revision))
            case let .paste(request, revision):
                guard let pid = request.pasteTarget else { continue }
                let task = Task { [weak self, services] in
                    do {
                        try Task.checkCancellation()
                        let dispatched = try await services.paste(pid, revision)
                        try Task.checkCancellation()
                        guard let self, case let .awaitingPaste(current, currentRevision) = self.state,
                              current.id == request.id, currentRevision == revision else { return }
                        self.pasteTask = nil
                        self.diagnostics(DiagnosticRecord(.paste, dispatched ? .succeeded : .cancelled, operationID: request.id))
                        self.send(.pasted(request.id, dispatched: dispatched))
                    } catch {
                        guard !Task.isCancelled else { return }
                        guard let self, case let .awaitingPaste(current, currentRevision) = self.state,
                              current.id == request.id, currentRevision == revision else { return }
                        self.pasteTask = nil
                        self.diagnostics(DiagnosticRecord(.paste, error is CancellationError ? .cancelled : .failed,
                                                          operationID: request.id))
                        self.send(.pasted(request.id, dispatched: false))
                    }
                }
                pasteTask = (request.id, task)
            case let .clear(request):
                guard context?.requestID == request.id else { continue }
                context?.store?.mutate(.clearExportedNotes(stackID: request.stack.id, notes: request.stack.notes),
                                       operationID: request.id) {
                    [weak self] outcome in self?.send(.cleared(request.id, outcome))
                }
            case let .report(message): context?.report(message)
            case .retry:
                diagnostics(DiagnosticRecord(.cleanup, .retry, operationID: context?.requestID))
                context?.store?.retryPendingMutations()
            case .cancelPaste: cancelPaste()
            }
        }
    }

    private func cancelPaste() {
        guard let work = pasteTask else { return }
        pasteTask = nil
        work.task.cancel()
        diagnostics(DiagnosticRecord(.paste, .cancelled, operationID: work.requestID))
    }

    func teardown() { send(.teardown) }
}
