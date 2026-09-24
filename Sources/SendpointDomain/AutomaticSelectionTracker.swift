import Foundation

public nonisolated struct AutomaticSelectionRequest: Equatable, Sendable {
    public var token: Int
    public var processIdentifier: pid_t
    public var pasteboardChangeCountBeforeDrag: Int

    public init(token: Int, processIdentifier: pid_t, pasteboardChangeCountBeforeDrag: Int) {
        self.token = token
        self.processIdentifier = processIdentifier
        self.pasteboardChangeCountBeforeDrag = pasteboardChangeCountBeforeDrag
    }
}

public nonisolated enum AutomaticSelectionEvent: Equatable, Sendable {
    case mouseDown(processIdentifier: pid_t, pasteboardChangeCount: Int)
    case mouseDragged
    case mouseUp
    case settle(AutomaticSelectionRequest, text: String?, pasteboardChangeCount: Int, now: Date)
    case settlePending(text: String?, pasteboardChangeCount: Int, now: Date)
    case abandon(AutomaticSelectionRequest)
    case take(processIdentifier: pid_t, pasteboardChangeCount: Int, now: Date)
    case discard
    case teardown
}

public nonisolated enum AutomaticSelectionEffect: Equatable, Sendable {
    case beginSettlement(AutomaticSelectionRequest)
    case cancelSettlement
    case accepted
    case took(String)
}

public nonisolated struct AutomaticSelectionTracker: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case dragging(AutomaticSelectionRequest, didDrag: Bool)
        case settling(AutomaticSelectionRequest)
        case available(
            text: String,
            processIdentifier: pid_t,
            pasteboardChangeCount: Int,
            capturedAt: Date
        )
        case tornDown
    }

    public private(set) var phase: Phase = .idle
    public private(set) var nextToken = 0

    public init() {}

    public var isTornDown: Bool { phase == .tornDown }

    public var settlementRequest: AutomaticSelectionRequest? {
        if case let .settling(request) = phase { return request }
        return nil
    }

    public mutating func update(_ event: AutomaticSelectionEvent) -> [AutomaticSelectionEffect] {
        guard phase != .tornDown else { return [] }
        switch event {
        case .teardown:
            phase = .tornDown
            return [.cancelSettlement]
        case let .mouseDown(processIdentifier, pasteboardChangeCount):
            guard processIdentifier > 0 else {
                phase = .idle
                return [.cancelSettlement]
            }
            nextToken += 1
            phase = .dragging(
                AutomaticSelectionRequest(
                    token: nextToken,
                    processIdentifier: processIdentifier,
                    pasteboardChangeCountBeforeDrag: pasteboardChangeCount
                ),
                didDrag: false
            )
            return [.cancelSettlement]
        case .mouseDragged:
            guard case let .dragging(request, _) = phase else { return [] }
            phase = .dragging(request, didDrag: true)
            return []
        case .mouseUp:
            guard case let .dragging(request, didDrag) = phase else { return [] }
            guard didDrag else {
                phase = .idle
                return []
            }
            phase = .settling(request)
            return [.beginSettlement(request)]
        case let .settle(request, text, pasteboardChangeCount, now):
            return settle(
                request,
                text: text,
                pasteboardChangeCount: pasteboardChangeCount,
                now: now
            )
        case let .settlePending(text, pasteboardChangeCount, now):
            guard case let .settling(request) = phase else { return [] }
            return settle(
                request,
                text: text,
                pasteboardChangeCount: pasteboardChangeCount,
                now: now
            )
        case let .abandon(request):
            guard case let .settling(active) = phase, active == request else { return [] }
            phase = .idle
            return []
        case let .take(processIdentifier, pasteboardChangeCount, now):
            guard case let .available(text, candidateProcess, candidateChangeCount, capturedAt) = phase
            else { return [] }
            phase = .idle
            guard candidateProcess == processIdentifier,
                  candidateChangeCount == pasteboardChangeCount
            else { return [] }
            let age = now.timeIntervalSince(capturedAt)
            guard age >= 0, age <= 15 else { return [] }
            return [.took(text)]
        case .discard:
            phase = .idle
            return [.cancelSettlement]
        }
    }

    private mutating func settle(
        _ request: AutomaticSelectionRequest,
        text: String?,
        pasteboardChangeCount: Int,
        now: Date
    ) -> [AutomaticSelectionEffect] {
        guard case let .settling(active) = phase, active == request else { return [] }
        guard pasteboardChangeCount != request.pasteboardChangeCountBeforeDrag else { return [] }
        guard let text, text.nonblank != nil else {
            phase = .idle
            return []
        }
        phase = .available(
            text: text,
            processIdentifier: request.processIdentifier,
            pasteboardChangeCount: pasteboardChangeCount,
            capturedAt: now
        )
        return [.accepted]
    }
}
