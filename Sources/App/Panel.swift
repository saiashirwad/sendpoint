import AppKit
import Core

/// The one window. Built at launch and only shown or hidden afterwards.
/// `render` is a function of World; the panel holds no state of its own.
final class Panel: NSPanel, NSTextViewDelegate {
    private let header = NSTextField(labelWithString: "")
    private let quote = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSTextView.scrollableTextView()
    private var text: NSTextView { scroll.documentView as! NSTextView }
    private let hint = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        quote.font = .systemFont(ofSize: 13)
        quote.textColor = .secondaryLabelColor
        quote.maximumNumberOfLines = 4
        quote.lineBreakMode = .byTruncatingTail
        quote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        text.font = .systemFont(ofSize: 15)
        text.isRichText = false
        text.allowsUndo = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 4)
        text.delegate = self
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false

        let stack = NSStackView(views: [header, quote, scroll, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 18, bottom: 14, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [quote, scroll] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
        }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    func render(_ w: World, speechStatus: String) {
        let draft: Draft
        let listening: Bool
        switch w.mode {
        case .idle:
            if isVisible { orderOut(nil) }
            return
        case .drafting(let d):
            draft = d
            listening = false
            setText(d.body)
        case .listening(let d, let partial):
            draft = d
            listening = true
            setText(partial.isEmpty ? d.body : (d.body.isEmpty ? partial : d.body + " " + partial))
        }

        let count = w.stacks[w.active].count
        let dots = (0..<stackCount).map { $0 == w.active ? "●" : "○" }.joined(separator: " ")
        header.stringValue = "\(dots)   Stack \(w.active + 1) · \(count) note\(count == 1 ? "" : "s")"
        quote.stringValue = draft.quote
        quote.isHidden = draft.quote.isEmpty
        text.isEditable = !listening
        text.textColor = listening ? .secondaryLabelColor : .labelColor
        hint.stringValue = listening
            ? "● Listening — release ⌘E (or press again) to finish · esc cancel"
            : speechStatus.isEmpty ? "↩ save · ⇧↩ new line · esc cancel · ⌘E speak · ⌥1–4 stack" : speechStatus

        if !isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2, y: frame.minY + frame.height * 0.62))
            }
            makeKeyAndOrderFront(nil)
            makeFirstResponder(text)
        }
    }

    /// Only touch the text view when World disagrees, so typing never resets the caret.
    private func setText(_ s: String) {
        guard text.string != s else { return }
        text.string = s
        text.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
        text.scrollToEndOfDocument(nil)
    }

    func textDidChange(_ notification: Notification) {
        send(.edit(text.string))
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)) where !NSEvent.modifierFlags.contains(.shift):
            send(.commit)
            return true
        case #selector(cancelOperation(_:)):
            send(.cancel)
            return true
        default:
            return false
        }
    }

    override func cancelOperation(_ sender: Any?) {
        send(.cancel)   // Esc while listening, when the text view isn't editable
    }
}
