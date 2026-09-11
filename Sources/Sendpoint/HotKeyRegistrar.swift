import Foundation

/// Owns the app's system-wide shortcuts: applies the stored bindings to
/// `HotKeyCenter` and reports the ones the system refused.
final class HotKeyRegistrar {
    /// Every configurable shortcut's action, supplied by the composition root.
    struct Actions {
        var voicePressed: () -> Void
        var voiceReleased: () -> Void
        var typedNote: () -> Void
        var copy: () -> Void
        var showStack: () -> Void
        var switchStack: (_ reverse: Bool) -> Void
        var nextStack: () -> Void
        var previousStack: () -> Void
        var clear: () -> Void
    }

    private let settings: AppSettings
    private let center: HotKeyCenter

    init(settings: AppSettings, center: HotKeyCenter = .shared) {
        self.settings = settings
        self.center = center
    }

    /// Applies every binding to the system and reports what was refused.
    /// A rejected replacement must not leave the previous binding live, so
    /// each name is unregistered before its replacement is attempted.
    @discardableResult
    func register(_ actions: Actions) -> [ShortcutRegistrationIssue] {
        var issues: [ShortcutRegistrationIssue] = []
        center.unregister(name: .switchSessionReverse)
        for slot in ShortcutSlot.allCases {
            // A rejected replacement must not leave the previous binding live.
            center.unregister(name: slot.hotKeyName)
            guard let combo = settings.combo(for: slot) else { continue }
            guard combo.isValid else {
                issues.append(.invalid(slot: slot, combo: combo))
                continue
            }
            if let conflict = settings.shortcutConflict(for: combo, excluding: slot) {
                issues.append(.conflict(slot: slot, combo: combo, reason: conflict))
                continue
            }
            let released: (() -> Void)? = slot == .voiceCapture ? actions.voiceReleased : nil
            let action: () -> Void
            switch slot {
            case .voiceCapture: action = actions.voicePressed
            case .capture: action = actions.typedNote
            case .copy: action = actions.copy
            case .stack: action = actions.showStack
            case .switchSession: action = { actions.switchStack(false) }
            case .nextStack: action = actions.nextStack
            case .previousStack: action = actions.previousStack
            case .clear: action = actions.clear
            }
            switch center.register(name: slot.hotKeyName, combo: combo, released: released,
                                   action: action) {
            case .registered:
                // ⇧ on the switch shortcut walks the cycle backwards. It is
                // claimed together with the shortcut, so a failure here is
                // only logged: the forward direction still works.
                if slot == .switchSession, let reverse = settings.switchSessionReverseCombo {
                    center.register(name: .switchSessionReverse, combo: reverse) {
                        actions.switchStack(true)
                    }
                }
            case .invalid:
                issues.append(.invalid(slot: slot, combo: combo))
            case let .failed(status):
                issues.append(.unavailable(slot: slot, combo: combo, status: status))
            }
        }
        return issues
    }

    /// Releases every name the app can register, including the temporary
    /// cycle keys owned elsewhere.
    func unregisterAll() {
        for name in HotKeyName.allCases {
            center.unregister(name: name)
        }
    }
}
