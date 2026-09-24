import AppKit
import Observation
import SendpointDomain
import SwiftUI

@Observable
final class StackReadoutModel {
    let store: StackStore
    var number = 1

    init(store: StackStore) {
        self.store = store
    }
}

struct StackReadoutView: View {
    let model: StackReadoutModel

    static let margin: CGFloat = 16
    static let height: CGFloat = 56

    var body: some View {
        let palette = OverlayPalette.dark
        let facts = StackUIFacts(store: model.store)
        HStack(spacing: 24) {
            if let stack = facts.stack(number: model.number) {
                StackReadoutLabel(stack: stack, numeralSize: 26, detailSize: 13)
            }
            StackStrip(stacks: facts.stacks.map { stack in
                StackItemFacts(id: stack.id, number: stack.number, noteCount: stack.noteCount,
                    isCurrent: stack.number == model.number, startedAt: stack.startedAt)
            }, size: 12, accent: palette.accent)
        }
        .fixedSize()
        .padding(.horizontal, 20)
        .frame(height: Self.height)
        .foregroundStyle(palette.ink)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(Self.margin)
    }
}

final class StackReadoutController {
    private enum Lifecycle { case active, tornDown }

    let panel: NSPanel
    private let model: StackReadoutModel
    private var lifecycle: Lifecycle = .active

    init(store: StackStore) {
        model = StackReadoutModel(store: store)
        let hosting = NSHostingView(rootView: StackReadoutView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = hosting
    }

    func show(number: Int) {
        guard lifecycle == .active else { return }
        model.number = number
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.contentView?.fittingSize ?? panel.frame.size
            let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 4)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        guard lifecycle == .active else { return }
        panel.orderOut(nil)
    }

    func teardown() {
        guard lifecycle == .active else { return }
        lifecycle = .tornDown
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }
}
