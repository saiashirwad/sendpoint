import Foundation

final class HotKeyRegistrar {
    struct Actions {
        var voicePressed: () -> Void
        var voiceReleased: () -> Void
        var typedNote: () -> Void
        var dictatePressed: () -> Void
        var dictateReleased: () -> Void
        var copy: () -> Void
        var showStack: () -> Void
        var selectStack: (_ number: Int) -> Void
        var clear: () -> Void
        var editLatest: () -> Void = {}
    }

    private let settings: ShortcutSettings
    private let center: HotKeyCenter
    private var actions: Actions?

    init(settings: ShortcutSettings, center: HotKeyCenter) {
        self.settings = settings
        self.center = center
    }

    @discardableResult
    func register(_ actions: Actions) -> [ShortcutRegistrationFailure] {
        self.actions = actions
        var failures: [ShortcutRegistrationFailure] = []
        let plan = settings.bindingPlan
        for slot in ShortcutSlot.allCases {
            center.unregister(name: .slot(slot))
            guard let combo = plan.bindings[slot] else { continue }
            let action: () -> Void
            var released: (() -> Void)?
            switch slot {
            case .voiceCapture: (action, released) = (actions.voicePressed, actions.voiceReleased)
            case .dictate: (action, released) = (actions.dictatePressed, actions.dictateReleased)
            case .capture: action = actions.typedNote
            case .copy: action = actions.copy
            case .stack: action = actions.showStack
            case let .selectStack(number): action = { actions.selectStack(number) }
            case .clear: action = actions.clear
            case .editLatest: action = actions.editLatest
            }
            switch center.register(name: .slot(slot), combo: combo, released: released,
                                   action: action) {
            case .registered:
                break
            case .invalid:
                preconditionFailure("Binding plan admitted an invalid shortcut")
            case let .failed(status):
                failures.append(ShortcutRegistrationFailure(slot: slot, combo: combo, status: status))
            }
        }
        settings.updateRegistrationFailures(failures)
        return failures
    }

    func rebind(_ proposed: KeyCombo, for slot: ShortcutSlot) throws {
        try settings.setShortcut(proposed, for: slot)
        applyCurrentBindings()
    }

    func clear(_ slot: ShortcutSlot) {
        settings.clearShortcut(for: slot)
        applyCurrentBindings()
    }

    func updateShortcut(_ proposed: KeyCombo?, for slot: ShortcutSlot) -> String? {
        if let proposed {
            do {
                try rebind(proposed, for: slot)
            } catch {
                return error.localizedDescription
            }
        } else {
            clear(slot)
        }
        return nil
    }

    func applyCurrentBindings() {
        guard let actions else { return }
        register(actions)
    }

    func unregisterAll() {
        center.unregisterAll()
    }
}
