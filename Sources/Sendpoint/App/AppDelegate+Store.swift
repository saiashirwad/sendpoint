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
                settingsWindowController?.storeDidBecomeAvailable(store)
                captureController.configure(store: store)
                buildPalette(store: store)
                let editor = LatestNoteEditor(store: store, blockedReason: { [weak self] in
                    guard let self else { return "Sendpoint is closing." }
                    if self.captureController.isOpen { return "Finish the current capture before editing a note." }
                    if self.palette?.hasUnfinishedInteraction == true {
                        return "Finish the edit in the stack before opening another note."
                    }
                    return nil
                })
                editor.onMessage = { [weak self] in self?.statusItemController.flash($0) }
                latestNoteEditor = LatestNoteEditorWindow(model: editor, surfaces: surfaces)
                let readout = StackReadoutController(store: store)
                stackReadout = readout
                stackSelector = StackSelector(
                    store: store,
                    showsReadout: { [weak self] in
                        guard let self else { return false }
                        return self.surfaces.visible.isDisjoint(with: [.palette, .captureEditor, .captureVoice, .latestNoteEditor])
                    },
                    showReadout: { [weak readout] in readout?.show(number: $0) },
                    hideReadout: { [weak readout] in readout?.hide() }
                )
                refreshStatusItem()
            } catch is CancellationError {
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
        if let store { captureController.send(.stackSelected(store.selectedStackID)) }
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
