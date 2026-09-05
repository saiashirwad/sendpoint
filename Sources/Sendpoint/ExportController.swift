import AppKit
import Observation
import SendpointDomain

struct ExportRequest: Equatable {
    let id: UUID
    let session: Session
    let markdown: String
    let clearAfterCopy: Bool
    let pasteTarget: pid_t?
}

enum ExportAction {
    case begin(ExportRequest)
    case copied(UUID, revision: Int?)
    case pasted(UUID, dispatched: Bool)
    case cleared(UUID, AnnotationStoreMutationOutcome)
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

    mutating func update(_ action: ExportAction) -> [ExportEffect] {
        guard self != .tornDown else { return [] }
        switch action {
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
        let report = ExportEffect.report("\(verb) \(request.session.entries.count) notes")
        self = request.clearAfterCopy ? .clearing(request) : .idle
        return request.clearAfterCopy ? [report, .clear(request)] : [report]
    }
    private mutating func fail(_ request: ExportRequest, _ message: String, retryable: Bool = false) -> [ExportEffect] {
        self = .failed(request, message, retryable: retryable)
        return [.report(message)]
    }
}

@MainActor
struct ExportServices {
    var write: (String) -> Int?
    var paste: (pid_t, Int) async throws -> Bool

    static var live: Self {
        Self(write: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string) ? pasteboard.changeCount : nil
        }, paste: { pid, revision in
            try await Task.sleep(for: .milliseconds(120))
            return try await SelectionCapture.paste(into: pid, expectedRevision: revision)
        })
    }
}

@MainActor
@Observable
final class ExportController {
    private(set) var state: ExportState = .idle
    @ObservationIgnored private let services: ExportServices
    @ObservationIgnored private var pasteTask: Task<Void, Never>?
    @ObservationIgnored private weak var store: AnnotationStore?
    @ObservationIgnored private var report: (String) -> Void = { _ in }

    init(services: ExportServices? = nil) { self.services = services ?? .live }

    func copy(store: AnnotationStore, sessionID: UUID, profile: Profile,
              pasteTarget: pid_t? = nil, report: @escaping (String) -> Void) {
        guard let session = store.sessions.first(where: { $0.id == sessionID }), !session.entries.isEmpty else {
            report("Nothing to copy")
            return
        }
        self.store = store
        self.report = report
        send(.begin(ExportRequest(id: UUID(), session: session,
            markdown: PromptComposer.markdown(session: session, profile: profile),
            clearAfterCopy: profile.clearSessionAfterExport, pasteTarget: pasteTarget)))
    }

    func copyNote(_ note: Annotation, report: (String) -> Void) {
        guard state != .tornDown else { return }
        // Changing the clipboard explicitly aborts any delayed stack paste.
        pasteTask?.cancel()
        pasteTask = nil
        if case let .awaitingPaste(request, _) = state { send(.pasted(request.id, dispatched: false)) }
        report(services.write(PromptComposer.noteMarkdown(note)) == nil ? "Couldn’t copy the note." : "Copied note")
    }

    func send(_ action: ExportAction) {
        let effects = state.update(action)
        for effect in effects {
            switch effect {
            case let .write(request): send(.copied(request.id, revision: services.write(request.markdown)))
            case let .paste(request, revision):
                guard let pid = request.pasteTarget else { continue }
                pasteTask = Task { [weak self, services] in
                    do {
                        try Task.checkCancellation()
                        let dispatched = try await services.paste(pid, revision)
                        try Task.checkCancellation()
                        guard let self else { return }
                        self.pasteTask = nil
                        self.send(.pasted(request.id, dispatched: dispatched))
                    } catch is CancellationError {
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.pasteTask = nil
                        self?.send(.pasted(request.id, dispatched: false))
                    }
                }
            case let .clear(request):
                store?.mutate(.clearExportedAnnotations(sessionID: request.session.id, entries: request.session.entries)) {
                    [weak self] outcome in self?.send(.cleared(request.id, outcome))
                }
            case let .report(message): report(message)
            case .retry: store?.retryPendingMutations()
            case .cancelPaste: pasteTask?.cancel(); pasteTask = nil
            }
        }
    }

    func teardown() { send(.teardown); store = nil; report = { _ in } }
}
