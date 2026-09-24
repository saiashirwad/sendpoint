import AppKit
import SendpointDomain

final class AutomaticSelectionMonitor {
    private var state = AutomaticSelectionTracker()
    private var eventMonitor: Any?
    private var settlementTask: Task<Void, Never>?
    private var settlementToken: Int?
    private var pending: [AutomaticSelectionEvent] = []
    private var isDraining = false
    private var acceptedSettlement = false
    private var taken: String?

    func start() {
        guard eventMonitor == nil, !state.isTornDown else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    func takeSelection(for processIdentifier: pid_t) -> String? {
        let pasteboard = NSPasteboard.general
        let now = Date()
        send(.settlePending(
            text: pasteboard.string(forType: .string),
            pasteboardChangeCount: pasteboard.changeCount,
            now: now
        ))
        taken = nil
        send(.take(
            processIdentifier: processIdentifier,
            pasteboardChangeCount: pasteboard.changeCount,
            now: now
        ))
        return taken
    }

    func discard() {
        send(.discard)
    }

    func teardown() {
        guard !state.isTornDown else { return }
        send(.teardown)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let pasteboard = NSPasteboard.general
            send(.mouseDown(
                processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
                pasteboardChangeCount: pasteboard.changeCount
            ))
        case .leftMouseDragged:
            send(.mouseDragged)
        case .leftMouseUp:
            send(.mouseUp)
        default:
            break
        }
    }

    private func send(_ event: AutomaticSelectionEvent) {
        pending.append(event)
        guard !isDraining else { return }
        isDraining = true
        while !pending.isEmpty {
            var next = state
            let effects = next.update(pending.removeFirst())
            state = next
            for effect in effects { run(effect) }
        }
        isDraining = false
    }

    private func run(_ effect: AutomaticSelectionEffect) {
        switch effect {
        case .cancelSettlement:
            settlementToken = nil
            settlementTask?.cancel()
            settlementTask = nil
        case let .beginSettlement(request):
            settlementTask?.cancel()
            settlementToken = request.token
            settlementTask = Task { [weak self] in
                await self?.poll(request)
                guard let self, self.settlementToken == request.token else { return }
                self.settlementTask = nil
                self.settlementToken = nil
            }
        case .accepted:
            acceptedSettlement = true
        case let .took(text):
            taken = text
        }
    }

    private func poll(_ request: AutomaticSelectionRequest) async {
        for _ in 0..<10 {
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return
            }
            guard !Task.isCancelled, settlementToken == request.token else { return }
            let pasteboard = NSPasteboard.general
            let text = pasteboard.string(forType: .string)
            let changeCount = pasteboard.changeCount
            let now = Date()
            guard !Task.isCancelled, settlementToken == request.token else { return }
            if didAccept(request, text: text, pasteboardChangeCount: changeCount, now: now) {
                return
            }
        }
        guard !Task.isCancelled, settlementToken == request.token else { return }
        guard state.settlementRequest == request else { return }
        send(.abandon(request))
    }

    private func didAccept(
        _ request: AutomaticSelectionRequest,
        text: String?,
        pasteboardChangeCount: Int,
        now: Date
    ) -> Bool {
        guard settlementToken == request.token, state.settlementRequest == request else { return false }
        acceptedSettlement = false
        send(.settle(
            request,
            text: text,
            pasteboardChangeCount: pasteboardChangeCount,
            now: now
        ))
        return acceptedSettlement
    }
}
