import AppKit
import SendpointDomain

final class AutomaticSelectionMonitor {
    private var state = AutomaticSelectionTracker()
    private var eventMonitor: Any?
    private var settlementTask: Task<Void, Never>?
    private var settlementToken: Int?

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
        return send(.take(
            processIdentifier: processIdentifier,
            pasteboardChangeCount: pasteboard.changeCount,
            now: now
        ))
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

    @discardableResult
    private func send(_ event: AutomaticSelectionEvent) -> String? {
        switch state.update(event) {
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
        case let .selection(text):
            return text
        case .none:
            break
        }
        return nil
    }

    private func poll(_ request: AutomaticSelectionRequest) async {
        for _ in 0..<10 {
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return
            }
            guard !Task.isCancelled, settlementToken == request.token,
                  state.settlementRequest == request else { return }
            let pasteboard = NSPasteboard.general
            let text = pasteboard.string(forType: .string)
            let changeCount = pasteboard.changeCount
            let now = Date()
            guard !Task.isCancelled, settlementToken == request.token,
                  state.settlementRequest == request else { return }
            send(.settle(request, text: text, pasteboardChangeCount: changeCount, now: now))
            if state.settlementRequest != request { return }
        }
        guard !Task.isCancelled, settlementToken == request.token else { return }
        guard state.settlementRequest == request else { return }
        send(.abandon(request))
    }
}
