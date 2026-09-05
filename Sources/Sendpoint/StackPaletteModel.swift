import AppKit
import Observation
import SendpointDomain

@MainActor
@Observable
final class StackPaletteModel {
    private(set) var state = PaletteWorkflow()
    let store: AnnotationStore
    let settings: AppSettings
    @ObservationIgnored private let onSelectProfile: (UUID) -> Void
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored private let export: ExportController
    @ObservationIgnored private let confirmDelete: (UUID, [Session], ClearedBatch?) -> Bool
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    init(store: AnnotationStore, settings: AppSettings, export: ExportController,
         onSelectProfile: @escaping (UUID) -> Void,
         confirmDelete: ((UUID, [Session], ClearedBatch?) -> Bool)? = nil) {
        self.store = store
        self.settings = settings
        self.export = export
        self.onSelectProfile = onSelectProfile
        self.confirmDelete = confirmDelete ?? {
            SessionDialogs.confirmsDelete(sessionID: $0, sessions: $1, lastCleared: $2)
        }
    }

    var projection: PaletteProjection {
        PaletteProjection(state: state, context: PaletteContext(sessions: store.sessions,
            currentSessionID: store.currentSessionID, lastCleared: store.lastCleared,
            profiles: settings.profiles, activeProfile: settings.activeProfile))
    }
    var query: String {
        get { state.query }
        set { send(.query(newValue)) }
    }
    var overlayQuery: String {
        get { state.overlayQuery }
        set { send(.overlayQuery(newValue)) }
    }

    @discardableResult
    func send(_ event: PaletteEvent) -> Bool {
        var update = PaletteUpdate(state: state, context: projection.context, operationID: UUID(), now: Date())
        let handled = update.update(event)
        state = update.state
        for effect in update.effects { run(effect) }
        return handled
    }

    private func run(_ effect: PaletteEffect) {
        switch effect {
        case let .mutate(id, mutation):
            store.mutate(mutation) { [weak self] outcome in self?.send(.mutationResult(id, outcome)) }
        case .retry: store.retryPendingMutations()
        case let .confirmDelete(id):
            let confirmed = confirmDelete(id, store.sessions, store.lastCleared)
            send(.deleteDecision(id, confirmed: confirmed))
        case let .copyStack(id):
            export.copy(store: store, sessionID: id, profile: settings.activeProfile) { [weak self] message in
                self?.showFlash(message)
            }
        case let .copyNote(note):
            export.copyNote(note) { [weak self] message in self?.showFlash(message) }
        case let .selectProfile(id): onSelectProfile(id)
        case let .openURL(url): NSWorkspace.shared.open(url)
        case .close:
            flashTask?.cancel()
            flashTask = nil
            onClose()
        case .beep: NSSound.beep()
        }
    }

    private func showFlash(_ message: String) {
        send(.copied(message))
        guard let generation = state.flash?.generation else { return }
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flashTask = nil
            self?.send(.clearFlash(generation))
        }
    }
}
