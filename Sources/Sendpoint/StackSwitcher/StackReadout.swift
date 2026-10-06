import AppKit
import SendpointDomain
import SwiftUI

struct StackReadoutView: View {
    let store: StackStore

    static let margin: CGFloat = Spacing.lg
    static let height: CGFloat = 56

    var body: some View {
        let palette = OverlayPalette.dark
        let facts = StackUIFacts(store: store)
        HStack(spacing: Spacing.xl) {
            if let stack = facts.current {
                StackReadoutLabel(stack: stack, numeralSize: 26, detailSize: 13)
            }
            StackStrip(stacks: facts.stacks, size: 12, accent: palette.accent)
        }
        .fixedSize()
        .padding(.horizontal, Spacing.xl)
        .frame(height: Self.height)
        .foregroundStyle(palette.ink)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(Self.margin)
    }
}

final class StackReadoutController {
    private enum Lifecycle { case active, tornDown }

    let panel: NSPanel
    private var lifecycle: Lifecycle = .active

    init(store: StackStore) {
        let hosting = NSHostingView(rootView: StackReadoutView(store: store))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = Ink.nsClear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = hosting
    }

    func show() {
        guard lifecycle == .active else { return }
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
