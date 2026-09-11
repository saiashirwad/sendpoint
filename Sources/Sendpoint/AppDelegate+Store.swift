import Foundation
import SendpointDomain

extension AppDelegate {
    func bootstrapStore() {
        bootstrapTask?.cancel()
        storeState = .loading
        refreshStatusItem()

        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            do {
                let store = try await StackStore(
                    persistence: .live(),
                    onChange: { [weak self] in self?.storeDidChange() }
                )
                guard !Task.isCancelled else {
                    store.teardown()
                    return
                }
                bootstrapTask = nil
                storeState = .available(store)
                captureController.configure(store: store)
                buildPalette(store: store)
                switcher = StackSwitcherController(
                    store: store,
                    settings: shortcuts,
                    hotKeyCenter: environment.hotKeyCenter,
                    surfaces: surfaces,
                    onOpenPalette: { [weak self] id in
                        self?.presentPalette(at: .stacks, highlighting: id)
                    },
                    onSwitched: { [weak self] stack in
                        self?.statusItemController.flash(stack.name)
                    }
                )
                refreshStatusItem()
            } catch is CancellationError {
                // App termination owns cancellation and teardown.
            } catch {
                guard !Task.isCancelled else { return }
                bootstrapTask = nil
                storeState = .unavailable(error.localizedDescription)
                Diag.log("store bootstrap failed: \(error)")
                refreshStatusItem()
            }
        }
    }

    func storeDidChange() {
        palette?.documentChanged()
        switcher?.documentChanged()
        refreshStatusItem()
    }

    var store: StackStore? {
        guard case let .available(store) = storeState else { return nil }
        return store
    }

    var statusMenuStoreStatus: StatusMenuStoreStatus {
        switch storeState {
        case .loading: .loading
        case .available: .available
        case let .unavailable(message): .unavailable(message)
        }
    }
}
