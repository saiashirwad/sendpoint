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

/// The destination button must accept a click while another app remains active.
final class CaptureHostingView<Content: View>: NSHostingView<Content> {
    // Swift 6.3.3 crashes in EarlyPerfInliner on this generic subclass's
    // synthesized deinitializer during release builds.
    @inline(never) deinit {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Native windows are resources, never a second source of workflow state.
final class CaptureWindows {
    private unowned let model: CaptureController
    private let surfaces: SurfaceCoordinator
    private let hotKeyCenter: HotKeyCenter
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

    init(model: CaptureController, surfaces: SurfaceCoordinator, hotKeyCenter: HotKeyCenter) {
        self.model = model
        self.surfaces = surfaces
        self.hotKeyCenter = hotKeyCenter
        surfaces.register(.captureEditor, transitions: .init(
            show: { [weak self] in self?.presentEditor() },
            hide: { [weak self] in self?.hide(.editor) },
            focus: { [weak self] in self?.focusEditor() }
        ))
        surfaces.register(.captureVoice, transitions: .init(
            show: { [weak self] in self?.presentVoice() },
            hide: { [weak self] in self?.hide(.voice) }
        ))
    }

    func show(_ surface: CaptureSurface) {
        guard surface != self.surface else { return }
        close()
        self.surface = surface
        switch surface {
        case .editor: surfaces.present(.captureEditor)
        case .voice: surfaces.present(.captureVoice)
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
        surfaces.focus(.captureEditor)
    }

    private func focusEditor() {
        panel?.presentActivated()
    }

    func stopEscapeHandling() {
        hotKeyCenter.unregister(name: .voiceEscape)
        if let voiceEscapeMonitor { NSEvent.removeMonitor(voiceEscapeMonitor) }
        voiceEscapeMonitor = nil
    }

    func close() {
        guard let surface else { return }
        surfaces.dismiss(surface == .editor ? .captureEditor : .captureVoice)
    }

    private func hide(_ hidden: CaptureSurface) {
        guard surface == hidden else { return }
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
        surfaces.unregister(.captureEditor)
        surfaces.unregister(.captureVoice)
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

        panel.presentActivated()
    }

    private func makeEditorPanel() -> CapturePanel {
        let hosting = CaptureHostingView(rootView: CaptureView(model: model))
        return Self.makeEditorPanel(contentView: hosting)
    }

    static func makeEditorPanel(contentView: NSView = NSView()) -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 290),
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
        panel.minSize = NSSize(width: 380, height: 270)
        panel.animationBehavior = .utilityWindow

        // The shared sheet draws its own rounded edge beneath the title bar.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = contentView
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

        let escapeRegistration = hotKeyCenter.registerRaw(
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
        let hosting = CaptureHostingView(rootView: VoiceCaptureView(
            model: model,
            meter: model.levelMeter
        ))
        let panel = Self.makeVoicePanel(contentView: hosting)
        panel.setContentSize(NSSize(width: Self.voiceOverlayWidth, height: hosting.fittingSize.height))
        return panel
    }

    static func makeVoicePanel(contentView: NSView = NSView()) -> CapturePanel {
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
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        panel.contentView = contentView
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

    /// Wide enough for the capsule plus a one-line failure message; the
    /// transparent margin gives the anchored destination popover room.
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
