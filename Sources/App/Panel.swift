import AppKit
import Core

/// The note card. Built at launch and only shown or hidden afterwards.
/// `render` is a function of World; the panel keeps only what it needs to draw.
final class Panel: NSPanel, NSTextViewDelegate {
    private let card = NSView()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private let placeholder = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let tether = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let orb = NSView()
    private let halo = CALayer()
    private let dot = CALayer()

    private var link: CADisplayLink?
    private var loudness: CGFloat = 0
    private var listening = false
    private var applied: Config?   // the config the card was last laid out for
    private var body: [NSAttributedString.Key: Any] = [:]
    private var lineHeight: CGFloat = 20

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)

        card.wantsLayer = true
        card.layer!.cornerRadius = cardRadius
        card.layer!.cornerCurve = .continuous
        rim.colors = [white(0.16), white(0.04)]
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.black.cgColor
        rimMask.lineWidth = 0.5
        rim.mask = rimMask
        card.layer!.addSublayer(rim)

        text.isRichText = false
        text.allowsUndo = true
        text.drawsBackground = false
        text.insertionPointColor = accent
        text.textContainerInset = .zero
        text.textContainer!.lineFragmentPadding = 0
        text.textContainer!.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.autoresizingMask = .width
        text.delegate = self
        scroll.documentView = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none

        placeholder.textColor = ink(0.32)
        name.font = sans(11.5, .medium)
        name.textColor = ink(0.9)
        count.font = mono(11)
        count.textColor = ink(0.45)
        tether.font = mono(11)
        tether.textColor = ink(0.5)
        status.font = sans(11.5, .medium)
        status.textColor = amber
        status.lineBreakMode = .byTruncatingTail
        divider.wantsLayer = true
        divider.layer!.backgroundColor = white(0.12)
        orb.wantsLayer = true
        orb.layer!.addSublayer(halo)
        orb.layer!.addSublayer(dot)

        for view in [scroll, placeholder, name, count, divider, tether, status, orb] { card.addSubview(view) }
        contentView = card
    }

    override var canBecomeKey: Bool { true }

    func render(_ w: World) {
        let draft: Draft
        let wasListening = listening
        switch w.mode {
        case .idle:
            if isVisible { orderOut(nil) }
            stopMeter()
            listening = false
            return
        case .drafting(let d):
            draft = d
            listening = false
            if wasListening || text.string != d.body { setText(NSAttributedString(string: d.body, attributes: body)) }
        case .listening(let d, let partial, _):
            draft = d
            listening = true
            let shown = NSMutableAttributedString(string: d.body, attributes: body)
            if !partial.isEmpty {
                var dim = body
                dim[.foregroundColor] = ink(0.55)
                let gap = d.body.isEmpty || d.body.last!.isWhitespace ? "" : " "
                shown.append(NSAttributedString(string: gap + partial, attributes: dim))
            }
            setText(shown)
        }

        if applied != w.config { layoutCard(w.config) }
        text.isEditable = !listening
        placeholder.stringValue = listening ? "Listening…" : "Add a note…"
        placeholder.isHidden = !text.string.isEmpty

        // Footer: stack name, count, selection size ........ status, orb.
        let notes = w.stacks[w.active].count
        let words = draft.quote.split(whereSeparator: \.isWhitespace).count
        name.stringValue = w.config.names[w.active]
        count.stringValue = "\(notes)"
        tether.stringValue = words == 1 ? "1 word selected" : "\(words) words selected"
        status.stringValue = w.voice.label
        divider.isHidden = words == 0
        tether.isHidden = words == 0
        status.isHidden = w.voice.label.isEmpty

        let width = card.frame.width
        let mid = padBottom + footerHeight / 2
        var x = padX
        place(name, &x, mid)
        x += 6
        place(count, &x, mid)
        if words > 0 {
            x += 10
            divider.frame = NSRect(x: x, y: mid - 6, width: 1, height: 12)
            x += 11
            place(tether, &x, mid)
        }
        orb.frame = NSRect(x: width - padX - 15, y: mid - 11, width: 22, height: 22)
        if !status.isHidden {
            status.sizeToFit()
            let w = min(status.frame.width, orb.frame.minX - 8 - (x + 12))
            status.frame = NSRect(x: orb.frame.minX - 6 - w, y: name.frame.minY,
                                  width: max(w, 0), height: status.frame.height)
        }
        if listening { startMeter() } else { stopMeter() }
        drawOrb()

        if !isVisible { present() }
    }

    // MARK: Layout

    private func place(_ label: NSTextField, _ x: inout CGFloat, _ mid: CGFloat) {
        label.sizeToFit()
        // Centre the caps, not the frame, so Geist and Martian Mono share a baseline.
        let font = label.font!
        let baseline = (mid - font.capHeight / 2).rounded()
        label.frame.origin = NSPoint(x: x, y: baseline + font.descender - (label.frame.height - (font.ascender - font.descender)) / 2)
        x = label.frame.maxX
    }

    private func layoutCard(_ c: Config) {
        applied = c
        let font = sans(c.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        body = [.font: font, .foregroundColor: ink(0.92), .paragraphStyle: paragraph]
        text.typingAttributes = body
        text.textStorage?.setAttributes(body, range: NSRange(location: 0, length: (text.string as NSString).length))
        placeholder.font = font
        lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font)) + 3

        let width = CGFloat(c.width)
        let textHeight = CGFloat(c.lines) * lineHeight
        let height = padTop + textHeight + gap + footerHeight + padBottom
        setContentSize(NSSize(width: width, height: height))
        card.frame = NSRect(x: 0, y: 0, width: width, height: height)
        card.layer!.backgroundColor = NSColor(white: 0.06, alpha: c.opacity).cgColor
        rim.frame = card.bounds
        rimMask.path = CGPath(roundedRect: card.bounds.insetBy(dx: 0.25, dy: 0.25),
                              cornerWidth: cardRadius - 0.25, cornerHeight: cardRadius - 0.25, transform: nil)
        scroll.frame = NSRect(x: padX, y: padBottom + footerHeight + gap, width: width - padX * 2, height: textHeight)
        text.frame.size.width = scroll.contentSize.width
        placeholder.sizeToFit()
        placeholder.frame = NSRect(x: padX - 2, y: scroll.frame.maxY - placeholder.frame.height,
                                   width: width - padX * 2, height: placeholder.frame.height)
        invalidateShadow()
    }

    /// Bottom-centre of the screen under the mouse, rising in.
    private func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let target = NSRect(x: (visible.midX - frame.width / 2).rounded(), y: visible.minY + 28,
                            width: frame.width, height: frame.height)
        setFrame(target.offsetBy(dx: 0, dy: -8), display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        makeFirstResponder(text)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    // MARK: Text

    private func setText(_ s: NSAttributedString) {
        text.textStorage?.setAttributedString(s)
        text.setSelectedRange(NSRange(location: s.length, length: 0))
        text.scrollToEndOfDocument(nil)
    }

    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !text.string.isEmpty
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

    // MARK: Orb

    private func startMeter() {
        guard link == nil else { return }
        link = card.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    private func stopMeter() {
        link?.invalidate()
        link = nil
        loudness = 0
    }

    @objc private func tick() {
        let target = CGFloat(speech.meter.level)
        loudness += (target - loudness) * (target > loudness ? 0.5 : 0.15)   // fast attack, slow release
        drawOrb()
    }

    private func drawOrb() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let l = pow(loudness, 1.3)
        let dotSize = listening ? 8 + 5 * l : 8
        let haloSize = listening ? 8 + 14 * l : 0
        dot.frame = NSRect(x: 11 - dotSize / 2, y: 11 - dotSize / 2, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = listening ? accent.cgColor : white(0.42)
        halo.frame = NSRect(x: 11 - haloSize / 2, y: 11 - haloSize / 2, width: haloSize, height: haloSize)
        halo.cornerRadius = haloSize / 2
        halo.backgroundColor = accent.withAlphaComponent(0.22).cgColor
        CATransaction.commit()
    }
}

// MARK: Look

private let cardRadius: CGFloat = 14
private let padX: CGFloat = 16
private let padTop: CGFloat = 14
private let padBottom: CGFloat = 8
private let footerHeight: CGFloat = 24
private let gap: CGFloat = 8

private let accent = NSColor(red: 0.98, green: 0.36, blue: 0.60, alpha: 1)
private let amber = NSColor(red: 0.98, green: 0.72, blue: 0.36, alpha: 1)
private func ink(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
private func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }

/// Geist and Martian Mono ship in the app bundle; a bare `swift run` falls back to system fonts.
private func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: weight == .medium ? "Geist-Medium" : "Geist-Regular", size: size)
        ?? .systemFont(ofSize: size, weight: weight)
}

private func mono(_ size: CGFloat) -> NSFont {
    NSFont(name: "MartianMono-NrRg", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}
