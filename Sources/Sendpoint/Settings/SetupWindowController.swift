import AppKit
import SendpointDomain
import SwiftUI

final class SetupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SetupWindowController: NSObject, NSWindowDelegate {
    private enum Lifecycle {
        case active
        case tornDown
    }

    private let window: NSPanel
    private let permissionState: PermissionController
    private let surfaces: SurfaceCoordinator
    private let tour = SetupTour()
    private let noteCount: () -> Int?
    private var lifecycle: Lifecycle = .active
    private var pollingTask: Task<Void, Never>?
    private var lastStep: Int?

    init(
        settings: AppSettings,
        permissionState: PermissionController,
        shortcuts: ShortcutSettings,
        voiceSettings: VoiceSettings,
        surfaces: SurfaceCoordinator,
        noteCount: @escaping () -> Int?,
        onComplete: @escaping () -> Void
    ) {
        let window = Self.makeWindow()
        self.permissionState = permissionState
        self.surfaces = surfaces
        self.noteCount = noteCount
        self.window = window
        super.init()
        let hosting = NSHostingView(rootView: SetupView(
            settings: settings,
            permissionState: permissionState,
            tour: tour,
            shortcuts: shortcuts,
            voiceSettings: voiceSettings,
            onComplete: onComplete,
            onDismiss: { [weak self] in self?.window.close() }
        ))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(SetupView.size)
        window.center()
        window.delegate = self
        surfaces.register(.setup, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.hide() }
        ))
    }

    static func makeWindow() -> NSPanel {
        let window = SetupPanel(
            contentRect: NSRect(origin: .zero, size: SetupView.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Sendpoint"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }

    func show() {
        guard lifecycle == .active else { return }
        surfaces.present(.setup)
    }

    private func present() {
        tour.send(.presented)
        startPolling()
        if !window.isVisible {
            window.center()
        }
        window.presentActivated()
    }

    private var currentStage: SetupHeroStage { permissionState.setupStage }

    private var currentStep: Int {
        let stage = currentStage
        return stage == .ready ? stage.step + tour.step.rawValue : stage.step
    }

    private func revealAfterStepChange() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() {
        stopPolling()
        window.orderOut(nil)
        window.close()
    }

    func teardown() {
        guard lifecycle == .active else { return }
        surfaces.unregister(.setup)
        lifecycle = .tornDown
        stopPolling()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    private func startPolling() {
        stopPolling()
        lastStep = currentStep
        let permissionState = permissionState
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.lifecycle == .active else { return }
                permissionState.refresh()
                if let count = self.noteCount() { self.tour.send(.noteCount(count)) }
                let step = self.currentStep
                if self.lastStep != step {
                    self.lastStep = step
                    self.revealAfterStepChange()
                }
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
        surfaces.userClosed(.setup)
    }
}
