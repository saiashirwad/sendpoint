import AppKit
import Carbon.HIToolbox
import SendpointDomain
import SwiftUI

final class LatestNoteEditorWindow {
    let model: LatestNoteEditor
    private let surfaces: SurfaceCoordinator
    private var panel: CapturePanel?
    private var keyMonitor: Any?

    init(model: LatestNoteEditor, surfaces: SurfaceCoordinator) {
        self.model = model
        self.surfaces = surfaces
        surfaces.register(.latestNoteEditor, transitions: .init(
            show: { [weak self] in self?.present() },
            hide: { [weak self] in self?.panel?.orderOut(nil) },
            focus: { [weak self] in self?.panel?.presentActivated() }
        ))
        model.onPresent = { [weak surfaces] in surfaces?.present(.latestNoteEditor) }
        model.onClose = { [weak surfaces] in surfaces?.dismiss(.latestNoteEditor) }
    }

    private func present() {
        if panel == nil {
            let hosting = CaptureHostingView(rootView: LatestNoteEditorView(model: model))
            hosting.sizingOptions = []
            hosting.safeAreaRegions = []
            let panel = CaptureWindows.makeEditorPanel(contentView: hosting)
            panel.title = "Edit latest note"
            panel.setContentSize(NSSize(width: 560, height: 360))
            panel.minSize = NSSize(width: 440, height: 300)
            panel.center()
            self.panel = panel
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.panel else { return event }
                if event.keyCode == UInt16(kVK_Escape) {
                    self.model.send(.dismiss)
                    return nil
                }
                if [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter)].contains(event.keyCode),
                   event.modifierFlags.contains(.command) {
                    self.model.send(.save)
                    return nil
                }
                return event
            }
        }
        installCloseHandler()
        panel?.presentActivated()
    }

    private func installCloseHandler() {
        panel?.onClose = { [weak self] in
            self?.installCloseHandler()
            self?.model.send(.dismiss)
        }
    }

    func teardown() {
        model.send(.teardown)
        surfaces.unregister(.latestNoteEditor)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.onClose = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}
