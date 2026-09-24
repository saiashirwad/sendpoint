import AppKit
import SendpointDomain

extension NSWindow {
    func presentActivated() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

final class SurfaceCoordinator {
    struct Transitions {
        var show: () -> Void
        var hide: () -> Void
        var focus: (() -> Void)?
    }

    private var state = SurfaceState()
    private var transitions: [Surface: Transitions] = [:]
    private let hasModalWindow: () -> Bool
    private let setRegularActivation: (Bool) -> Void
    private var pending: [SurfaceEvent] = []
    private var isDraining = false

    var visible: Set<Surface> { state.visible }

    init(
        hasModalWindow: @escaping () -> Bool = { NSApp.modalWindow != nil },
        setRegularActivation: @escaping (Bool) -> Void = { regular in
            NSApplication.shared.setActivationPolicy(regular ? .regular : .accessory)
        }
    ) {
        self.hasModalWindow = hasModalWindow
        self.setRegularActivation = setRegularActivation
    }

    func register(_ surface: Surface, transitions: Transitions) {
        self.transitions[surface] = transitions
    }

    func unregister(_ surface: Surface) {
        dismiss(surface)
        transitions[surface] = nil
    }

    func present(_ surface: Surface) {
        send(.present(surface, registered: transitions[surface] != nil))
    }

    func focus(_ surface: Surface) {
        send(.focus(surface))
    }

    func dismiss(_ surface: Surface) {
        send(.dismiss(surface))
    }

    func userClosed(_ surface: Surface) {
        send(.userClosed(surface))
    }

    func resignedKey(_ surface: Surface) {
        send(.resignedKey(surface, modal: hasModalWindow()))
    }

    func teardown() {
        guard !state.isTornDown else { return }
        send(.teardown)
        transitions.removeAll()
    }

    private func send(_ event: SurfaceEvent) {
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

    private func run(_ effect: SurfaceEffect) {
        switch effect {
        case let .show(surface):
            transitions[surface]?.show()
        case let .hide(surface):
            transitions[surface]?.hide()
        case let .focus(surface):
            transitions[surface]?.focus?()
        case let .setRegularActivation(regular):
            setRegularActivation(regular)
        }
    }
}
