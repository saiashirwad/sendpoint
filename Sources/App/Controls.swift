import AppKit
import Core

// The settings window's look: the 1.x palette and controls, drawn in AppKit.
// Controls hold no settings of their own. `render` sets what they show; a press calls `onPress`.

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 48
}

enum Radius {
    static let panel: CGFloat = 14
    static let card: CGFloat = 10
    static let chip: CGFloat = 6
}

/// Colors that follow light and dark.
enum Ink {
    static let paper = dynamic(dark: NSColor(white: 0.07, alpha: 1), light: .white)
    static let well = dynamic(dark: NSColor(white: 0.04, alpha: 0.85), light: NSColor(white: 0.965, alpha: 0.85))
    static let raised = dynamic(dark: NSColor(white: 0.15, alpha: 1), light: .white)
    static let accent = dynamic(dark: NSColor(red: 0.98, green: 0.36, blue: 0.60, alpha: 1),
                                light: NSColor(red: 0.86, green: 0.10, blue: 0.40, alpha: 1))
    static let amber = dynamic(dark: NSColor(red: 0.98, green: 0.72, blue: 0.36, alpha: 1),
                               light: NSColor(red: 0.76, green: 0.48, blue: 0.08, alpha: 1))
    static let hairline = dynamic(dark: primary(0.12), light: primary(0.10))
    static let primary = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let tertiary = NSColor.tertiaryLabelColor

    static func primary(_ alpha: CGFloat) -> NSColor { NSColor.labelColor.withAlphaComponent(alpha) }

    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Geist and Martian Mono ship in the app bundle; a bare `swift run` falls back to system fonts.
func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let face = weight == .semibold ? "Geist-SemiBold" : weight == .medium ? "Geist-Medium" : "Geist-Regular"
    return NSFont(name: face, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let face = weight == .regular ? "MartianMono-NrRg" : "MartianMono-NrMd"
    return NSFont(name: face, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
}

func label(_ text: String = "", _ font: NSFont = sans(13), _ color: NSColor = Ink.primary) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

/// A small uppercase mono caption: section labels, the status card's kicker.
func caps(_ text: String, size: CGFloat, tracking: CGFloat, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: text.uppercased(), attributes: [
        .font: mono(size, .medium), .kern: tracking, .foregroundColor: color,
    ])
}

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

func pin(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
    view.translatesAutoresizingMaskIntoConstraints = false
    if let width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
    if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
}

func row(_ views: [NSView], spacing: CGFloat, align: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = spacing
    stack.alignment = align
    return stack
}

func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.spacing = spacing
    stack.alignment = .leading
    return stack
}

final class Spacer: NSView {
    init() {
        super.init(frame: .zero)
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A flat fill, optionally rounded and outlined. Redraws itself when the appearance flips.
class Fill: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat = 0
    var capsule = false

    init(_ color: NSColor? = nil, radius: CGFloat = 0) {
        self.color = color
        self.radius = radius
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    var shape: NSBezierPath {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let r = capsule ? rect.height / 2 : radius
        return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let color {
            color.setFill()
            radius == 0 && !capsule ? bounds.fill() : shape.fill()
        }
        if let stroke {
            stroke.setStroke()
            shape.stroke()
        }
    }
}

/// One device pixel of `Ink.hairline`.
final class Hairline: Fill {
    init(vertical: Bool = false) {
        super.init(Ink.hairline)
        translatesAutoresizingMaskIntoConstraints = false
        let thin = 1 / (NSScreen.main?.backingScaleFactor ?? 2)
        (vertical ? widthAnchor : heightAnchor).constraint(equalToConstant: thin).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: Pressable

/// A view that acts as a button: hover tracking, press on mouse-up inside, VoiceOver press.
class Pressable: Fill {
    var onPress: () -> Void = {}
    var isEnabled = true { didSet { if isEnabled != oldValue { restyle() } } }
    private(set) var hovering = false

    init(title: String) {
        super.init()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Called whenever hover or enabled changes. Subclasses set their colors here.
    func restyle() {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { hovering = false; restyle() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
    }
    override func accessibilityPerformPress() -> Bool {
        if isEnabled { onPress() }
        return isEnabled
    }
}

/// A capsule of text: a chip in a choice row, or an outlined pill button.
final class Chip: Pressable {
    enum Kind { case choice, pill }
    let kind: Kind
    private let text: NSTextField
    var isSelected = false { didSet { if isSelected != oldValue { restyle() } } }

    init(_ title: String, kind: Kind = .choice) {
        self.kind = kind
        text = label(title, kind == .pill ? sans(12, .medium) : sans(13, .medium))
        super.init(title: title)
        capsule = true
        addSubview(text)
        pin(self, height: 28)
        text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.md),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.md),
        ])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func restyle() {
        switch kind {
        case .choice:
            color = isSelected ? Ink.primary : Ink.primary(hovering ? 0.09 : 0.055)
            text.textColor = isSelected ? Ink.paper : Ink.primary
        case .pill:
            color = hovering && isEnabled ? Ink.raised : nil
            stroke = Ink.primary(hovering && isEnabled ? 0.22 : 0.14)
            text.textColor = isEnabled ? Ink.primary : Ink.tertiary
        }
        setAccessibilitySelected(isSelected)
    }
}

/// A round − or + beside a stepper's value.
final class Glyph: Pressable {
    private let image = NSImageView()

    init(_ name: String, title: String) {
        super.init(title: title)
        capsule = true
        image.image = symbol(name, 10, .semibold)
        addSubview(image)
        pin(self, width: 22, height: 22)
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func restyle() {
        color = Ink.primary(hovering && isEnabled ? 0.09 : 0.055)
        image.contentTintColor = !isEnabled ? Ink.primary(0.2) : hovering ? Ink.primary : Ink.secondary
    }
}

/// − value +. Sends the value one step either side; `step` clamps it.
final class Stepper: NSStackView {
    let minus: Glyph
    let plus: Glyph
    private let value = label("", mono(12, .medium))

    init(_ title: String) {
        minus = Glyph("minus", title: "Less \(title.lowercased())")
        plus = Glyph("plus", title: "More \(title.lowercased())")
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = Space.sm
        value.alignment = .center
        pin(value, width: 44)
        for view in [minus, value, plus] { addArrangedSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func render(_ text: String, canLess: Bool, canMore: Bool) {
        if value.stringValue != text { value.stringValue = text }
        minus.isEnabled = canLess
        plus.isEnabled = canMore
    }
}

// MARK: Key recorder

/// Click, then press a chord. It sends `.record` and `.set(.key)`; `step` decides what sticks,
/// and `render` says whether this one is still listening.
final class KeyRecorder: NSView {
    let action: Action
    private var shortcut: Shortcut?
    private var recording = false
    private var hovering = false

    init(_ action: Action) {
        self.action = action
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(actionTitles[action.rawValue]) shortcut")
    }
    required init?(coder: NSCoder) { fatalError() }

    func render(_ shortcut: Shortcut?, recording: Bool) {
        guard shortcut != self.shortcut || recording != self.recording else { return }
        self.shortcut = shortcut
        self.recording = recording
        setAccessibilityValue(text)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(64, ceil(textSize.width) + Space.md * 2), height: 28)
    }

    override func becomeFirstResponder() -> Bool {
        send(.record(action))
        return true
    }

    override func resignFirstResponder() -> Bool {
        if world.recording == action { send(.record(nil)) }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) } else { window?.makeFirstResponder(self) }
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self) ?? false
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(event.keyCode), flags.isEmpty) {
        case (53, true): window?.makeFirstResponder(nil)                    // esc: keep what was there
        case (51, true), (117, true): send(.set(.key(action, nil)))         // delete: turn it off
        default: send(.set(.key(action, Shortcut(code: Int(event.keyCode), mods: carbonMods(flags)))))
        }
        if world.recording != action, window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    private var text: String {
        if recording { return "Press keys…" }
        return shortcut.map(shortcutLabel) ?? "Not set"
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let set = !recording && shortcut != nil
        let color = recording ? Ink.secondary : set ? Ink.primary(0.85) : Ink.tertiary
        return [.font: sans(13, shortcut == nil && !recording ? .regular : .medium),
                .foregroundColor: color, .kern: set ? 0.6 : 0]
    }

    private var textSize: NSSize { (text as NSString).size(withAttributes: attributes) }

    override func draw(_ dirtyRect: NSRect) {
        let cap = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: Radius.chip, yRadius: Radius.chip)
        let rim = hovering ? Ink.primary(0.18) : Ink.hairline
        if recording {
            Ink.accent.withAlphaComponent(0.10).setFill()
            cap.fill()
            Ink.accent.setStroke()
            cap.lineWidth = 1.5
        } else {
            if shortcut != nil {
                Ink.raised.setFill()
                cap.fill()
            }
            rim.setStroke()
            cap.lineWidth = 1
        }
        cap.stroke()
        let size = textSize
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

private func carbonMods(_ flags: NSEvent.ModifierFlags) -> Int {
    var mods = 0
    if flags.contains(.command) { mods |= modCmd }
    if flags.contains(.option) { mods |= modOpt }
    if flags.contains(.control) { mods |= modCtrl }
    if flags.contains(.shift) { mods |= modShift }
    return mods
}

// MARK: Aurora

/// The status card's wash: pink and lavender from the top left, sky from the top right.
final class Aurora: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.isDark
        let pink = dark ? NSColor(red: 0.62, green: 0.24, blue: 0.44, alpha: 1) : NSColor(red: 1.00, green: 0.74, blue: 0.87, alpha: 1)
        let lavender = dark ? NSColor(red: 0.42, green: 0.36, blue: 0.62, alpha: 1) : NSColor(red: 0.84, green: 0.82, blue: 0.98, alpha: 1)
        let sky = dark ? NSColor(red: 0.30, green: 0.42, blue: 0.56, alpha: 1) : NSColor(red: 0.80, green: 0.88, blue: 0.98, alpha: 1)
        Ink.raised.setFill()
        bounds.fill()
        let warm = NSGradient(colors: [pink.withAlphaComponent(0.8), lavender.withAlphaComponent(0.7), .clear],
                              atLocations: [0, 0.45, 1], colorSpace: .sRGB)
        warm?.draw(in: bounds, angle: -65)
        let cool = NSGradient(colors: [sky.withAlphaComponent(0.6), .clear])
        cool?.draw(in: bounds, angle: -135)
    }
}
