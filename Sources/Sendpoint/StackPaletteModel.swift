import AppKit
import Observation
import SendpointDomain
@Observable
final class StackPaletteModel {
    private(set) var state = PaletteWorkflow()
    let store: StackStore
    let settings: TemplateSettings
    let shortcuts: ShortcutSettings
    let voiceSettings: VoiceSettings
    @ObservationIgnored private let onSelectTemplate: (UUID) -> Void
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored private let export: ExportController
    @ObservationIgnored private let confirmDelete: (UUID, [Stack], ClearedBatch?) -> Bool
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [PaletteEvent] = []
    @ObservationIgnored private var isDraining = false

    init(store: StackStore, settings: TemplateSettings, shortcuts: ShortcutSettings,
         voiceSettings: VoiceSettings, export: ExportController,
         onSelectTemplate: @escaping (UUID) -> Void,
         confirmDelete: ((UUID, [Stack], ClearedBatch?) -> Bool)? = nil) {
        self.store = store
        self.settings = settings
        self.shortcuts = shortcuts
        self.voiceSettings = voiceSettings
        self.export = export
        self.onSelectTemplate = onSelectTemplate
        self.confirmDelete = confirmDelete ?? {
            StackDialogs.confirmsDelete(stackID: $0, stacks: $1, lastCleared: $2)
        }
    }

    var projection: PaletteProjection {
        PaletteProjection(state: state, context: PaletteContext(stacks: store.stacks,
            currentStackID: store.currentStackID, lastCleared: store.lastCleared,
            templates: settings.templates, activeTemplate: settings.activeTemplate))
    }
    var query: String {
        get { state.query }
        set { send(.query(newValue)) }
    }
    var overlayQuery: String {
        get { state.overlayQuery }
        set { send(.overlayQuery(newValue)) }
    }

    /// Whether the event was handled. An event sent while another is being
    /// applied waits its turn and reports itself handled.
    @discardableResult
    func send(_ event: PaletteEvent) -> Bool {
        pending.append(event)
        guard !isDraining else { return true }
        isDraining = true
        defer { isDraining = false }
        var handled = true
        while !pending.isEmpty {
            var update = PaletteUpdate(state: state, context: projection.context, operationID: UUID(), now: Date())
            handled = update.update(pending.removeFirst())
            state = update.state
            for effect in update.effects { run(effect) }
        }
        return handled
    }

    private func run(_ effect: PaletteEffect) {
        switch effect {
        case let .mutate(id, mutation):
            store.mutate(mutation) { [weak self] outcome in self?.send(.mutationResult(id, outcome)) }
        case .retry: store.retryPendingMutations()
        case let .confirmDelete(id):
            let confirmed = confirmDelete(id, store.stacks, store.lastCleared)
            send(.deleteDecision(id, confirmed: confirmed))
        case let .copyStack(id):
            export.copy(store: store, stackID: id, template: settings.activeTemplate) { [weak self] message in
                self?.showFlash(message)
            }
        case let .copyNote(note):
            export.copyNote(note) { [weak self] message in self?.showFlash(message) }
        case let .selectTemplate(id): onSelectTemplate(id)
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
