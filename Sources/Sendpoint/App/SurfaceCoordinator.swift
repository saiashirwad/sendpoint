import AppKit

extension NSWindow {
    func presentActivated() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

enum Surface: CaseIterable, Hashable {
    case palette
    case settings
    case setup
    case captureEditor
    case captureVoice
}

final class SurfaceCoordinator {
    struct Transitions {
        var show: () -> Void
        var hide: () -> Void
        var focus: (() -> Void)?
    }

    private var transitions: [Surface: Transitions] = [:]
    private(set) var visible: Set<Surface> = []
    private let hasModalWindow: () -> Bool
    private let setRegularActivation: (Bool) -> Void
    private var usesRegularActivation = false

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
        switch surface {
        case .captureEditor:
            for hidden in [Surface.palette, .settings] {
                dismiss(hidden)
            }
        case .palette, .settings, .setup, .captureVoice:
            break
        }
        guard let transition = transitions[surface] else { return }
        visible.insert(surface)
        synchronizeActivation()
        transition.show()
    }

    func focus(_ surface: Surface) {
        guard visible.contains(surface) else { return }
        transitions[surface]?.focus?()
    }

    func dismiss(_ surface: Surface) {
        guard visible.remove(surface) != nil else { return }
        transitions[surface]?.hide()
        synchronizeActivation()
    }

    func userClosed(_ surface: Surface) {
        visible.remove(surface)
        synchronizeActivation()
    }

    func resignedKey(_ surface: Surface) {
        guard !hasModalWindow() else { return }
        dismiss(surface)
    }

    func teardown() {
        for surface in Surface.allCases where visible.contains(surface) {
            dismiss(surface)
        }
        transitions.removeAll()
    }

    private func synchronizeActivation() {
        let needsRegularActivation = visible.contains { surface in
            switch surface {
            case .settings:
                true
            case .palette, .setup, .captureEditor, .captureVoice:
                false
            }
        }
        guard needsRegularActivation != usesRegularActivation else { return }
        usesRegularActivation = needsRegularActivation
        setRegularActivation(needsRegularActivation)
    }
}
