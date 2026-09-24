import Foundation

public nonisolated enum Surface: CaseIterable, Hashable, Sendable {
    case palette
    case settings
    case setup
    case captureEditor
    case captureVoice
    case latestNoteEditor
}

public nonisolated enum SurfaceEvent: Equatable, Sendable {
    case present(Surface, registered: Bool)
    case focus(Surface)
    case dismiss(Surface)
    case userClosed(Surface)
    case resignedKey(Surface, modal: Bool)
    case teardown
}

public nonisolated enum SurfaceEffect: Equatable, Sendable {
    case show(Surface)
    case hide(Surface)
    case focus(Surface)
    case setRegularActivation(Bool)
}

public nonisolated struct SurfaceState: Equatable, Sendable {
    public enum Lifecycle: Equatable, Sendable {
        case live
        case tornDown
    }

    public var lifecycle: Lifecycle = .live
    public var visible: Set<Surface> = []
    public private(set) var usesRegularActivation = false

    public init() {}

    public var isTornDown: Bool { lifecycle == .tornDown }

    // Activation is reported before show and after hide.
    public mutating func update(_ event: SurfaceEvent) -> [SurfaceEffect] {
        guard lifecycle != .tornDown else { return [] }
        switch event {
        case .teardown:
            var effects: [SurfaceEffect] = []
            for surface in Surface.allCases {
                effects.append(contentsOf: hide(surface))
            }
            lifecycle = .tornDown
            return effects
        case let .present(surface, registered):
            var effects: [SurfaceEffect] = []
            switch surface {
            case .captureEditor, .latestNoteEditor:
                effects.append(contentsOf: hide(.palette))
                effects.append(contentsOf: hide(.settings))
            case .palette, .settings, .setup, .captureVoice:
                break
            }
            guard registered else { return effects }
            visible.insert(surface)
            effects.append(contentsOf: synchronizeActivation())
            effects.append(.show(surface))
            return effects
        case let .focus(surface):
            guard visible.contains(surface) else { return [] }
            return [.focus(surface)]
        case let .dismiss(surface):
            return hide(surface)
        case let .userClosed(surface):
            visible.remove(surface)
            return synchronizeActivation()
        case let .resignedKey(surface, modal):
            guard !modal else { return [] }
            return hide(surface)
        }
    }

    private mutating func hide(_ surface: Surface) -> [SurfaceEffect] {
        guard visible.remove(surface) != nil else { return [] }
        return [.hide(surface)] + synchronizeActivation()
    }

    private mutating func synchronizeActivation() -> [SurfaceEffect] {
        let needsRegularActivation = visible.contains { surface in
            switch surface {
            case .settings:
                true
            case .palette, .setup, .captureEditor, .captureVoice, .latestNoteEditor:
                false
            }
        }
        guard needsRegularActivation != usesRegularActivation else { return [] }
        usesRegularActivation = needsRegularActivation
        return [.setRegularActivation(needsRegularActivation)]
    }
}
