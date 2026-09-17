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

    static let size = CGSize(width: 260, height: 96)

    var body: some View {
        let palette = OverlayPalette.dark
        let facts = StackUIFacts(store: model.store)
        HStack(spacing: 18) {
            if let stack = facts.stack(number: model.number) {
                StackReadoutLabel(stack: stack, numeralSize: 26, detailSize: 13)
            }
            Spacer(minLength: 0)
            StackStrip(stacks: facts.stacks.map { stack in
                StackItemFacts(id: stack.id, number: stack.number, noteCount: stack.noteCount,
                    isCurrent: stack.number == model.number, startedAt: stack.startedAt)
            }, size: 12, accent: palette.accent)
        }
        .padding(.horizontal, 20)
        .frame(width: Self.size.width - 32, height: Self.size.height - 40)
        .foregroundStyle(palette.ink)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: Ink.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

final class StackReadoutController {
    private enum Lifecycle { case active, tornDown }

    private let panel: NSPanel
    private let model: StackReadoutModel
    private var lifecycle: Lifecycle = .active

    init(store: StackStore) {
        model = StackReadoutModel(store: store)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: StackReadoutView.size),
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
        panel.contentView = NSHostingView(rootView: StackReadoutView(model: model))
    }

    func show(number: Int) {
        guard lifecycle == .active else { return }
        model.number = number
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 4))
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
