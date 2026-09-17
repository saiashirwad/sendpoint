import AppKit
import SwiftUI

struct KeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?
    var clearable = false

    init(combo: Binding<KeyCombo?>, clearable: Bool = false) {
        _combo = combo
        self.clearable = clearable
    }

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onChange = { combo = $0 }
        view.combo = combo
        view.clearable = clearable
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.combo = combo
        nsView.clearable = clearable
    }
}

final class KeyRecorderView: NSView {
    var onChange: ((KeyCombo?) -> Void)?
    var clearable = false

    var combo: KeyCombo? {
        didSet { redraw() }
    }

    private var recording = false {
        didSet { redraw() }
    }

    private var hovering = false {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?

    private static let height: CGFloat = 28
    private static let minimumWidth: CGFloat = 64
    private static let sidePadding: CGFloat = 11

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        let width = ceil(textSize.width) + Self.sidePadding * 2
        return NSSize(width: max(Self.minimumWidth, width), height: Self.height)
    }

    private func redraw() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        let plainDelete = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            && (event.keyCode == 51 || event.keyCode == 117)
        if clearable, plainDelete {
            combo = nil
            recording = false
            window?.makeFirstResponder(nil)
            onChange?(nil)
            return
        }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
        guard candidate.isValid else { NSSound.beep(); return }
        combo = candidate
        recording = false
        window?.makeFirstResponder(nil)
        onChange?(candidate)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    // MARK: - Drawing

    private enum Look {
        case set, unset, recording
    }

    private var look: Look {
        if recording { return .recording }
        return combo == nil ? .unset : .set
    }

    private var text: String {
        switch look {
        case .recording: "Press keys…"
        case .set: combo?.displayString ?? ""
        case .unset: "Not set"
        }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let color: NSColor = switch look {
        case .recording: .secondaryLabelColor
        case .set: NSColor.labelColor.withAlphaComponent(0.85)
        case .unset: .tertiaryLabelColor
        }
        return [
            .font: NSFont.ui(13, weight: look == .unset ? .regular : .medium),
            .foregroundColor: color,
            .kern: look == .set ? 0.6 : 0,
        ]
    }

    private var textSize: NSSize {
        (text as NSString).size(withAttributes: attributes)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 7
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cap = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        switch look {
        case .set:
            if !effectiveAppearance.isDark {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.05)
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 1.5
                shadow.set()
                Ink.nsRaised.setFill()
                cap.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                Ink.nsRaised.setFill()
                cap.fill()
            }
            (hovering ? NSColor.labelColor.withAlphaComponent(0.18) : Ink.nsHairline).setStroke()
            cap.lineWidth = 1
            cap.stroke()
        case .unset:
            (hovering ? NSColor.labelColor.withAlphaComponent(0.18) : Ink.nsHairline).setStroke()
            cap.lineWidth = 1
            cap.stroke()
        case .recording:
            Ink.nsAccent.withAlphaComponent(0.10).setFill()
            cap.fill()
            Ink.nsAccent.setStroke()
            cap.lineWidth = 1.5
            cap.stroke()
        }

        let size = textSize
        (text as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
