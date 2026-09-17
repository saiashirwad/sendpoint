import AppKit
import SwiftUI

// MARK: - Plumbing

struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

final class ScrollHandle {
    weak var scrollView: NSScrollView?

    var viewportHeight: CGFloat { scrollView?.contentView.bounds.height ?? 0 }

    func isAtBottomEdge(_ frame: CGRect, margin: CGFloat = 6) -> Bool {
        frame.maxY + margin <= viewportHeight + 0.5
    }

    @discardableResult
    func reveal(_ frame: CGRect, anchor: UnitPoint) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let clip = scrollView.contentView
        let viewport = clip.bounds.height
        let content = document.bounds.height
        let currentTop = document.isFlipped
            ? clip.bounds.origin.y
            : content - viewport - clip.bounds.origin.y
        let top = revealedScrollOffset(
            currentTop: currentTop, frame: frame, viewportHeight: viewport,
            contentHeight: content, anchor: anchor
        )
        let unclamped = revealedScrollOffset(
            currentTop: currentTop, frame: frame, viewportHeight: viewport,
            contentHeight: .infinity, anchor: anchor
        )
        var origin = clip.bounds.origin
        origin.y = document.isFlipped ? top : content - viewport - top
        clip.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clip)
        return abs(top - unclamped) < 0.5
    }
}

struct ScrollProbe: NSViewRepresentable {
    let handle: ScrollHandle

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.handle = handle
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.handle = handle
        nsView.attach()
    }

    final class Probe: NSView {
        var handle: ScrollHandle?

        override init(frame: NSRect) {
            super.init(frame: frame)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attach()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            guard let scrollView = enclosingScrollView else { return }
            handle?.scrollView = scrollView
            scrollView.scrollerStyle = .overlay
        }
    }
}

struct WindowVisibilityReporter: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onChange = { isVisible = $0 }
    }

    static func dismantleNSView(_ nsView: ReporterView, coordinator: ()) {
        nsView.teardown()
    }

    final class ReporterView: NSView {
        var onChange: ((Bool) -> Void)?
        private var reportTask: Task<Void, Never>?

        deinit { reportTask?.cancel() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            reportTask?.cancel()
            guard let window else { report(false); return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(reportCurrent),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification, object: window
            )
            reportCurrent()
        }

        @objc private func reportCurrent() {
            guard let window else { report(false); return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            reportTask?.cancel()
            reportTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.reportTask = nil
                self.onChange?(visible)
            }
        }

        @objc private func windowWillClose() { report(false) }

        func teardown() {
            NotificationCenter.default.removeObserver(self)
            reportTask?.cancel()
            reportTask = nil
            onChange = nil
        }
    }
}
