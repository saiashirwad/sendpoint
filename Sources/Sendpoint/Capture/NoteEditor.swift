import AppKit
import SwiftUI

struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let ink: NSColor
    let isEditable: Bool
    let focusRequest: Int
    let onSave: () -> Void
    let onDiscard: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Note")
        textView.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Save") { onSave(); return true },
            NSAccessibilityCustomAction(name: "Discard") { onDiscard(); return true },
        ])

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NoteTextView else { return }
        context.coordinator.parent = self

        let style = NSMutableParagraphStyle()
        style.lineSpacing = VoiceCaptureLayout.transcriptLineSpacing
        let font = NSFont.ui(fontSize)
        let color = ink.withAlphaComponent(0.92)
        if textView.font != font || textView.textColor != color {
            textView.defaultParagraphStyle = style
            textView.font = font
            textView.textColor = color
            textView.insertionPointColor = ink
            textView.typingAttributes = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            textView.placeholder = NSAttributedString(string: placeholder, attributes: [
                .font: font, .foregroundColor: ink.withAlphaComponent(0.35), .paragraphStyle: style,
            ])
        }
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.undoManager.removeAllActions()
            textView.needsDisplay = true
        }
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            textView.takeFocus()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        var focusRequest = 0
        let undoManager = UndoManager()

        init(_ parent: NoteEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.needsDisplay = true
            parent.text = textView.string
        }
    }
}

final class NoteTextView: NSTextView {
    var placeholder = NSAttributedString() {
        didSet { needsDisplay = true }
    }
    private var wantsFocus = false

    func takeFocus() {
        guard let window else {
            wantsFocus = true
            return
        }
        window.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocus, let window else { return }
        wantsFocus = false
        window.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        placeholder.draw(at: textContainerOrigin)
    }
}
