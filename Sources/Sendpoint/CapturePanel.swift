import AppKit
import SendpointDomain
import SwiftUI

/// A floating panel that can take keyboard focus and, crucially, does **not**
/// hide when another app takes over. That is what lets Wispr Flow, Hex, or any
/// other dictation tool run on top of it while the note field stays alive.
final class CapturePanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performClose(_ sender: Any?) {
        guard let onClose else {
            super.performClose(sender)
            return
        }
        self.onClose = nil
        onClose()
    }
}

/// Native windows are resources, never a second source of workflow state.
@MainActor
final class CaptureWindows {
    private unowned let model: CaptureController
    private var panel: CapturePanel?
    private var keyMonitor: Any?
    private var voiceEscapeMonitor: Any?
    private var surface: CaptureSurface?

    init(model: CaptureController) { self.model = model }

    func show(_ surface: CaptureSurface) {
        guard surface != self.surface else { return }
        close()
        self.surface = surface
        switch surface {
        case .editor: presentEditor()
        case .voice: presentVoice()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 {
                if self.surface == .voice { self.model.voiceEscape() }
                else { self.model.send(.dismiss) }
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 76), event.modifierFlags.contains(.command) {
                self.model.send(.save)
                return nil
            }
            return event
        }
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func stopEscapeHandling() {
        HotKeyCenter.shared.unregister(name: "voiceEscape")
        if let voiceEscapeMonitor { NSEvent.removeMonitor(voiceEscapeMonitor) }
        voiceEscapeMonitor = nil
    }

    func close() {
        stopEscapeHandling()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.onClose = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        surface = nil
    }

    private func installVoiceEscapeFallback() {
        voiceEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.model.voiceEscape() }
        }
    }

    private func presentEditor() {
        let captured = model.state.session?.target?.captured
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.onClose = { [weak self] in self?.model.send(.dismiss) }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 380, height: 220)
        panel.animationBehavior = .utilityWindow

        let view = CaptureView(model: model)
        // The hosting view fills the whole frame, title-bar strip included, so
        // the material runs edge to edge under the transparent title bar.
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting

        position(panel, near: captured?.screenRect)

        self.panel = panel

        // Synchronous: the stack window must be out of the way before we
        // activate, or activating drags it forward with the panel.
        NotificationCenter.default.post(name: .captureWillPresent, object: nil)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Puts the overlay on screen without activating the app, so the front
    /// app keeps focus while its selection is still being read.
    private func presentVoice() {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onClose = { [weak self] in self?.model.send(.cancelVoice) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: VoiceCaptureView(
            model: model,
            meter: model.levelMeter
        ))
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: Self.voiceOverlayWidth, height: hosting.fittingSize.height))
        positionVoiceOverlay(panel)
        self.panel = panel

        let escapeRegistration = HotKeyCenter.shared.registerRaw(
            name: "voiceEscape",
            keyCode: 53,
            carbonModifiers: 0,
            pressed: { [weak self] in self?.model.voiceEscape() }
        )
        if case .failed = escapeRegistration {
            installVoiceEscapeFallback()
        }
        panel.orderFrontRegardless()
    }

    // MARK: - Placement

    private func position(_ panel: NSPanel, near selectionRect: CGRect?) {
        let size = panel.frame.size
        var origin: NSPoint

        if let rect = selectionRect, let screen = screenContaining(quartzRect: rect) {
            // Quartz rects are top-left origin; flip into AppKit coordinates.
            let flippedY = flipY(quartzRect: rect)
            origin = NSPoint(x: rect.midX - size.width / 2, y: flippedY - size.height - 12)
            if origin.y < screen.visibleFrame.minY + 8 {
                origin.y = flippedY + rect.height + 12
            }
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 16)
        }

        let screen = screenContaining(point: NSPoint(x: origin.x + size.width / 2, y: origin.y))
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    /// Wide enough for the capsule plus a one-line failure message. The panel
    /// is transparent and ignores the mouse, so the extra width is invisible.
    private static let voiceOverlayWidth: CGFloat = 680

    private func positionVoiceOverlay(_ panel: NSPanel) {
        let screen = screenContaining(point: NSEvent.mouseLocation) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        // The overlay view carries its own shadow padding, so sit a little
        // lower than the capsule should visually land.
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 4
        )
        panel.setFrameOrigin(origin)
    }

    private func flipY(quartzRect rect: CGRect) -> CGFloat {
        // Quartz global space is anchored at the top-left of the primary display.
        guard let primary = NSScreen.screens.first else { return rect.minY }
        return primary.frame.maxY - rect.minY
    }

    private func screenContaining(quartzRect rect: CGRect) -> NSScreen? {
        let point = NSPoint(x: rect.midX, y: flipY(quartzRect: rect))
        return screenContaining(point: point)
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

}

extension Notification.Name {
    static let captureWillPresent = Notification.Name("Sendpoint.captureWillPresent")
}
