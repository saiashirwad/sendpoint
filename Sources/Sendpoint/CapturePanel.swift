import AppKit
import Carbon.HIToolbox
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
final class CaptureWindows {
    private unowned let model: CaptureController
    private var panel: CapturePanel?
    /// Built once and kept: constructing a panel and its SwiftUI hosting
    /// view costs tens of milliseconds, which would sit between the hotkey
    /// and the first sample of audio or the first typed letter. Showing one
    /// again is a reposition.
    private var voicePanel: CapturePanel?
    private var editorPanel: CapturePanel?
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
            if event.keyCode == UInt16(kVK_Escape) {
                if self.surface == .voice { self.model.send(.voiceEscape) }
                else { self.model.send(.dismiss) }
                return nil
            }
            if (event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)),
               event.modifierFlags.contains(.command) {
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
        HotKeyCenter.shared.unregister(name: .voiceEscape)
        if let voiceEscapeMonitor { NSEvent.removeMonitor(voiceEscapeMonitor) }
        voiceEscapeMonitor = nil
    }

    func close() {
        stopEscapeHandling()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.onClose = nil
        panel?.orderOut(nil)
        panel = nil
        surface = nil
    }

    func discardSurfaces() {
        close()
        for kept in [voicePanel, editorPanel] {
            kept?.contentView = nil
            kept?.close()
        }
        voicePanel = nil
        editorPanel = nil
    }

    /// Call at launch, when nobody is waiting, so the first note pays
    /// nothing for its window.
    func prepareSurfaces() {
        if voicePanel == nil { voicePanel = makeVoicePanel() }
        if editorPanel == nil { editorPanel = makeEditorPanel() }
    }

    private func installVoiceEscapeFallback() {
        voiceEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            MainActor.assumeIsolated { self?.model.send(.voiceEscape) }
        }
    }

    private func presentEditor() {
        let captured = model.state.session?.target?.captured
        if editorPanel == nil { editorPanel = makeEditorPanel() }
        guard let panel = editorPanel else { return }
        panel.onClose = { [weak self] in self?.model.send(.dismiss) }
        position(panel, near: captured?.screenRect)
        self.panel = panel

        model.onWillPresentEditor?()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeEditorPanel() -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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
        return panel
    }

    /// Puts the overlay on screen without activating the app, so the front
    /// app keeps focus while its selection is still being read.
    private func presentVoice() {
        if voicePanel == nil { voicePanel = makeVoicePanel() }
        guard let panel = voicePanel else { return }
        panel.onClose = { [weak self] in self?.model.send(.cancelVoice) }
        positionVoiceOverlay(panel)
        self.panel = panel

        let escapeRegistration = HotKeyCenter.shared.registerRaw(
            name: .voiceEscape,
            keyCode: UInt16(kVK_Escape),
            carbonModifiers: 0,
            pressed: { [weak self] in self?.model.send(.voiceEscape) }
        )
        if case .failed = escapeRegistration {
            installVoiceEscapeFallback()
        }
        panel.orderFrontRegardless()
    }

    private func makeVoicePanel() -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
        return panel
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
