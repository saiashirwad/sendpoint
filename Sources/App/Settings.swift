import AppKit
import AVFoundation
import Core

/// The settings window. Built at launch, shown from the menu. Every control sends an Event;
/// `render` copies World onto the controls and decides nothing.
final class Settings: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let window: NSWindow
    private let tabs: [Tab]
    private let pages: [NSScrollView]
    private let status = StatusCard()

    // Capture
    private let voiceChips = [Chip("Hold to talk"), Chip("Tap to start and stop")]
    private let voiceNote = footnote()
    // Card
    private let lines = Stepper("Lines")
    private let fontSize = Stepper("Font size")
    private let width = Stepper("Width")
    private let opacity = Stepper("Opacity")
    // Stacks
    private let numbers = (0..<stackCount).map { Number($0) }
    private let names = (0..<stackCount).map { _ in NameField() }
    private let counts = (0..<stackCount).map { _ in label("", sans(13), Ink.secondary) }
    private let currents = (0..<stackCount).map { _ in label() }
    // System
    private let accessibility = label("", sans(13), Ink.secondary)
    private let grant = Chip("Grant access", kind: .pill)
    private let microphone = label("", sans(13), Ink.secondary)
    private let microphoneSettings = Chip("Open Settings", kind: .pill)
    private let problems = footnote(Ink.amber)
    private let version = label("", sans(13), Ink.secondary)
    // Every shortcut row, and the amber note under each group.
    private var recorders: [KeyRecorder] = []
    private var notices: [(actions: [Action], label: NSTextField)] = []
    private var shown: Shown?

    static let size = NSSize(width: 920, height: 600)

    override init() {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        tabs = [
            Tab("Capture", "waveform", .capture), Tab("Card", "captions.bubble", .card),
            Tab("Stacks", "rectangle.stack", .stacks), Tab("System", "gearshape", .system),
        ]
        pages = Pane.allCases.map { _ in NSScrollView() }
        super.init()

        window.title = "Sendpoint Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "Settings")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentMinSize = Self.size
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")

        let root = Fill(Ink.paper)
        let sidebar = makeSidebar()
        let divider = Hairline(vertical: true)
        for view in [sidebar, divider] + pages {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        let contents = [capturePage(), cardPage(), stacksPage(), systemPage()]
        for (scroll, content) in zip(pages, contents) {
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
                scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: root.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
            page(scroll, content)
        }
        window.contentView = root
        wire()
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        shown = nil
        render(world)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }

    // MARK: Render

    /// What the window last drew, so typing in the note card doesn't redraw settings.
    private struct Shown: Equatable {
        var config: Config
        var pane: Pane
        var recording: Action?
        var notice: Notice?
        var counts: [Int]
        var active: Int
        var trusted: Bool
        var microphone: AVAuthorizationStatus
        var speech: String
        var keyProblems: [String]
    }

    func render(_ w: World) {
        guard window.isVisible else { return }
        let now = Shown(config: w.config, pane: w.pane, recording: w.recording, notice: w.notice,
                        counts: w.stacks.map(\.count), active: w.active, trusted: AXIsProcessTrusted(),
                        microphone: AVCaptureDevice.authorizationStatus(for: .audio),
                        speech: speech.status, keyProblems: Keys.problems)
        guard now != shown else { return }
        shown = now
        let c = w.config

        for tab in tabs { tab.isSelected = tab.pane == w.pane }
        for (i, page) in pages.enumerated() { page.isHidden = i != w.pane.rawValue }
        status.render(w, setup: setupNeeded(now))

        voiceChips[0].isSelected = c.voice == .hold
        voiceChips[1].isSelected = c.voice == .tap
        voiceNote.stringValue = c.voice == .hold
            ? "Hold the voice shortcut while you talk. Let go and the note is saved."
            : "Tap the voice shortcut to start, and tap it again to save the note."

        lines.render("\(c.lines)", canLess: c.lines > linesRange.lowerBound, canMore: c.lines < linesRange.upperBound)
        fontSize.render(points(c.fontSize), canLess: c.fontSize > fontSizeRange.lowerBound,
                        canMore: c.fontSize < fontSizeRange.upperBound)
        width.render(points(c.width), canLess: c.width > widthRange.lowerBound, canMore: c.width < widthRange.upperBound)
        opacity.render("\(Int((c.opacity * 100).rounded()))%", canLess: c.opacity > opacityRange.lowerBound,
                       canMore: c.opacity < opacityRange.upperBound)

        for i in 0..<stackCount {
            let current = i == w.active
            numbers[i].render(current: current)
            if names[i].currentEditor() == nil { names[i].stringValue = c.names[i] }
            let n = w.stacks[i].count
            counts[i].stringValue = n == 0 ? "Empty" : n == 1 ? "1 note" : "\(n) notes"
            counts[i].textColor = n == 0 ? Ink.tertiary : Ink.secondary
            currents[i].attributedStringValue = caps(current ? "Current" : "", size: 10.5, tracking: 1.4, color: Ink.tertiary)
        }

        for recorder in recorders {
            recorder.render(c.keys[recorder.action.rawValue], recording: w.recording == recorder.action)
        }
        for (actions, text) in notices {
            let notice = w.notice.flatMap { actions.contains($0.action) ? $0.text : nil }
            text.stringValue = notice ?? ""
            text.isHidden = notice == nil
        }

        accessibility.stringValue = now.trusted ? "Granted" : "Needed to read the selection and paste"
        grant.isHidden = now.trusted
        switch now.microphone {
        case .authorized: microphone.stringValue = now.speech.isEmpty ? "Granted" : now.speech
        case .notDetermined: microphone.stringValue = "Asked for on first use"
        default: microphone.stringValue = "Off. Voice notes need it"
        }
        microphoneSettings.isHidden = now.microphone == .authorized || now.microphone == .notDetermined
        let all = c.problems + now.keyProblems
        problems.stringValue = all.map { "⚠︎ " + $0 }.joined(separator: "\n")
        problems.isHidden = all.isEmpty
        let info = Bundle.main.infoDictionary
        version.stringValue = (info?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Development build"
    }

    private func setupNeeded(_ s: Shown) -> StatusCard.Setup? {
        if !s.trusted { return .accessibility }
        if s.microphone == .denied || s.microphone == .restricted { return .microphone }
        if !s.speech.isEmpty { return .speech(s.speech) }
        return nil
    }

    // MARK: Events

    private func wire() {
        for tab in tabs { tab.onPress = { [pane = tab.pane] in send(.show(pane)) } }
        voiceChips[0].onPress = { send(.set(.voice(.hold))) }
        voiceChips[1].onPress = { send(.set(.voice(.tap))) }
        lines.minus.onPress = { send(.set(.lines(world.config.lines - 1))) }
        lines.plus.onPress = { send(.set(.lines(world.config.lines + 1))) }
        fontSize.minus.onPress = { send(.set(.fontSize(world.config.fontSize - 1))) }
        fontSize.plus.onPress = { send(.set(.fontSize(world.config.fontSize + 1))) }
        width.minus.onPress = { send(.set(.width(world.config.width - 20))) }
        width.plus.onPress = { send(.set(.width(world.config.width + 20))) }
        opacity.minus.onPress = { send(.set(.opacity(world.config.opacity - 0.05))) }
        opacity.plus.onPress = { send(.set(.opacity(world.config.opacity + 0.05))) }
        for i in 0..<stackCount {
            numbers[i].onPress = { send(.select(i)) }
            names[i].tag = i
            names[i].delegate = self
        }
        grant.onPress = { openPrivacy("Privacy_Accessibility") }
        microphoneSettings.onPress = { openPrivacy("Privacy_Microphone") }
        status.onPress = { [weak self] in
            guard let self, let shown else { return }
            switch setupNeeded(shown) {
            case .accessibility: openPrivacy("Privacy_Accessibility")
            case .microphone: openPrivacy("Privacy_Microphone")
            case .speech: send(.show(.system))
            case nil: send(.open)
            }
        }
    }

    func controlTextDidEndEditing(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        send(.set(.name(field.tag, field.stringValue)))
        field.stringValue = world.config.names[field.tag]   // "" comes back as "Stack N"
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:))
        else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) { textView.string = world.config.names[control.tag] }
        window.makeFirstResponder(nil)
        return true
    }

    /// Leaving the window ends a recording, so the global shortcuts come back.
    func windowDidResignKey(_ notification: Notification) { window.makeFirstResponder(nil) }
    func windowDidBecomeKey(_ notification: Notification) { render(world) }
    func windowWillClose(_ notification: Notification) { window.makeFirstResponder(nil) }

    // MARK: Pages

    private func capturePage() -> NSView {
        page([
            section("Recording", [column([row(voiceChips, spacing: Space.sm), voiceNote], spacing: Space.md)],
                    stacked: true),
            shortcuts("Shortcuts", [
                (.speak, "Voice note", "Saves what you say to the stack"),
                (.note, "Typed note", "Quotes the selected text"),
            ]),
        ])
    }

    private func cardPage() -> NSView {
        page([
            section("Card", [
                setting("Lines", hint: "Text the card shows before it scrolls", lines),
                setting("Font size", fontSize),
                setting("Width", width),
                setting("Opacity", opacity),
            ], footnote: "The note card opens at the bottom of the screen under the pointer."),
        ])
    }

    private func stacksPage() -> NSView {
        let rows = (0..<stackCount).map { i in
            keyRow(Action(rawValue: Action.stack1.rawValue + i)!,
                   row([numbers[i], names[i].box, counts[i], currents[i]], spacing: Space.lg))
        }
        for count in counts { pin(count, width: 64) }
        return page([
            shortcutSection("Stacks", rows, [.stack1, .stack2, .stack3, .stack4],
                            footnote: "Click a number to make it the current stack. Click a name to rename it."),
            shortcuts("Current stack", [
                (.paste, "Paste the stack", "As Markdown, then clears it"),
                (.open, "Open the stack", "In your Markdown editor"),
            ]),
        ])
    }

    private func systemPage() -> NSView {
        let editConfig = Chip("Open config.toml", kind: .pill)
        editConfig.onPress = { openFile(configURL) }
        let folder = configURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return page([
            section("Permissions", [
                setting("Accessibility", hint: nil, accessibility, grant),
                setting("Microphone", hint: nil, microphone, microphoneSettings),
            ], footnote: "Audio never leaves this Mac."),
            section("Config file", [setting("config.toml", hint: folder, editConfig)],
                    footnote: "Everything here is saved to this file, and edits to it show up here.", extra: problems),
            section("About", [setting("Sendpoint", hint: nil, version)]),
        ])
    }

    // MARK: Building blocks

    private func makeSidebar() -> NSView {
        let sidebar = Fill(Ink.well)
        let name = label("Sendpoint", sans(17, .semibold))
        name.attributedStringValue = NSAttributedString(string: "Sendpoint", attributes: [
            .font: sans(17, .semibold), .kern: -0.2, .foregroundColor: Ink.primary,
        ])
        let dot = Fill(Ink.accent)
        dot.capsule = true
        pin(dot, width: 6, height: 6)
        let wordmark = row([name, dot], spacing: Space.sm)
        let list = column(tabs, spacing: Space.xs)
        for tab in tabs { tab.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        for view in [wordmark, list, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(view)
        }
        NSLayoutConstraint.activate([
            wordmark.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 52 + Space.xl),
            wordmark.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Space.md + Space.md),
            list.topAnchor.constraint(equalTo: wordmark.bottomAnchor, constant: Space.xl),
            list.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Space.md),
            list.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -Space.md),
            status.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Space.md),
            status.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -Space.md),
            status.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -Space.md),
            status.heightAnchor.constraint(equalToConstant: 124),
        ])
        return sidebar
    }

    /// Sections stacked down a page, at most 640 wide.
    private func page(_ sections: [NSView]) -> NSView {
        let stack = column(sections, spacing: Space.xl)
        stack.edgeInsets = NSEdgeInsets(top: Space.xxl, left: Space.xxl, bottom: Space.xxl, right: Space.xxl)
        for view in sections { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -Space.xxl * 2).isActive = true }
        return stack
    }

    private func page(_ scroll: NSScrollView, _ content: NSView) {
        let document = Flipped()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        let clip = scroll.contentView
        let capped = content.widthAnchor.constraint(equalTo: document.widthAnchor)
        capped.priority = .defaultHigh
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 640 + Space.xxl * 2),
            capped,
        ])
    }

    /// LABEL, then rows split by hairlines, then a footnote.
    private func section(_ title: String, _ rows: [NSView], footnote note: String? = nil,
                         stacked: Bool = false, extra: NSView? = nil) -> NSView {
        let heading = label()
        heading.attributedStringValue = caps(title, size: 10.5, tracking: 1.4, color: Ink.tertiary)
        var body: [NSView] = []
        for (i, view) in rows.enumerated() {
            if i > 0 { body.append(Hairline()) }
            body.append(view)
        }
        let list = column(body, spacing: 0)
        if stacked { list.edgeInsets = NSEdgeInsets(top: Space.md, left: 0, bottom: Space.sm, right: 0) }
        for view in body { view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        var parts: [NSView] = [heading, list]
        if let note { parts.append(footnote(note)) }
        if let extra { parts.append(extra) }
        let out = column(parts, spacing: Space.xs)
        list.widthAnchor.constraint(equalTo: out.widthAnchor).isActive = true
        return out
    }

    /// Title, a quieter hint beside it, and controls at the right edge. 44 tall.
    private func setting(_ title: String, hint: String? = nil, _ trailing: NSView...) -> NSView {
        let name = label(title, sans(14, .medium))
        var left: [NSView] = [name]
        if let hint { left.append(label(hint, sans(13), Ink.secondary)) }
        for view in left.dropFirst() { view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        let leading = row(left, spacing: Space.md, align: .firstBaseline)
        return line(leading, row(trailing, spacing: Space.md))
    }

    private func line(_ leading: NSView, _ trailing: NSView) -> NSView {
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        let out = row([leading, Spacer(), trailing], spacing: Space.md)
        out.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return out
    }

    private func keyRow(_ action: Action, _ leading: NSView) -> NSView {
        let recorder = KeyRecorder(action)
        recorder.setContentHuggingPriority(.required, for: .horizontal)
        recorders.append(recorder)
        return line(leading, recorder)
    }

    private func shortcuts(_ title: String, _ specs: [(Action, String, String)]) -> NSView {
        let rows = specs.map { action, name, hint in
            keyRow(action, row([label(name, sans(14, .medium)), label(hint, sans(13), Ink.secondary)],
                               spacing: Space.md, align: .firstBaseline))
        }
        return shortcutSection(title, rows, specs.map(\.0))
    }

    private func shortcutSection(_ title: String, _ rows: [NSView], _ actions: [Action], footnote note: String? = nil) -> NSView {
        let notice = footnote(Ink.amber)
        notice.isHidden = true
        notices.append((actions, notice))
        return section(title, rows, footnote: note, extra: notice)
    }
}

private func footnote(_ text: String) -> NSTextField {
    let field = footnote()
    field.stringValue = text
    return field
}

private func footnote(_ color: NSColor = Ink.secondary) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: "")
    field.font = sans(12.5)
    field.textColor = color
    field.preferredMaxLayoutWidth = 600
    return field
}

private func points(_ x: Double) -> String {
    x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x)
}

private func openPrivacy(_ anchor: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
}

private final class Flipped: NSView {
    override var isFlipped: Bool { true }
}

// MARK: Sidebar pieces

/// A sidebar row: symbol and title, raised when it's the open page.
private final class Tab: Pressable {
    let pane: Pane
    private let icon = NSImageView()
    private let title: NSTextField
    var isSelected = false { didSet { if isSelected != oldValue { restyle() } } }

    init(_ name: String, _ symbolName: String, _ pane: Pane) {
        self.pane = pane
        title = label(name, sans(14, .medium))
        super.init(title: name)
        radius = Radius.card
        icon.image = symbol(symbolName, 14, .medium)
        pin(icon, width: 18)
        let content = row([icon, title], spacing: Space.md)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        pin(self, height: 34)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.md),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func restyle() {
        color = isSelected ? Ink.raised : hovering ? Ink.primary(0.03) : nil
        stroke = isSelected ? Ink.hairline : nil
        icon.contentTintColor = isSelected ? Ink.primary : Ink.secondary
        title.textColor = isSelected || hovering ? Ink.primary : Ink.primary(0.72)
        setAccessibilitySelected(isSelected)
    }
}

/// The current stack, or the one setup step still missing. Clicking acts on it.
private final class StatusCard: Pressable {
    enum Setup: Equatable {
        case accessibility, microphone
        case speech(String)
    }

    private let dot = Fill()
    private let kicker = label()
    private let arrow = NSImageView()
    private let title = label("", sans(15, .semibold))
    private let detail = label("", mono(10.5), Ink.secondary)

    init() {
        super.init(title: "Status")
        wantsLayer = true
        layer?.cornerRadius = Radius.panel
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        let wash = Aurora()
        dot.capsule = true
        pin(dot, width: 5, height: 5)
        arrow.image = symbol("arrow.up.right", 10, .semibold)
        arrow.contentTintColor = Ink.tertiary
        arrow.isHidden = true
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.preferredMaxLayoutWidth = 140
        let top = row([dot, kicker, Spacer(), arrow], spacing: Space.sm)
        let bottom = column([title, detail], spacing: Space.xs)
        for view in [wash, top, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            wash.leadingAnchor.constraint(equalTo: leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: trailingAnchor),
            wash.topAnchor.constraint(equalTo: topAnchor),
            wash.bottomAnchor.constraint(equalTo: bottomAnchor),
            top.topAnchor.constraint(equalTo: topAnchor, constant: Space.lg),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.lg),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.lg),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.lg),
            bottom.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Space.lg),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Space.lg),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// A layer border draws above the wash; resolved here so it follows light and dark.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { self.layer?.borderColor = Ink.hairline.cgColor }
    }

    override func restyle() { arrow.isHidden = !hovering }

    func render(_ w: World, setup: Setup?) {
        let copy: (String, String, String)
        switch setup {
        case .accessibility: copy = ("Setup", "Needs Accessibility", "Click to grant")
        case .microphone: copy = ("Setup", "Microphone is off", "Click to open Settings")
        case .speech(let status): copy = ("Setup", status, "Voice notes wait for this")
        case nil:
            let n = w.stacks[w.active].count
            copy = ("Current stack", w.config.names[w.active],
                    n == 0 ? "No notes yet" : n == 1 ? "1 note · click to open" : "\(n) notes · click to open")
        }
        dot.color = setup == nil ? Ink.accent : Ink.amber
        kicker.attributedStringValue = caps(copy.0, size: 9.5, tracking: 1.3, color: Ink.secondary)
        title.stringValue = copy.1
        detail.stringValue = copy.2
        setAccessibilityLabel("\(copy.1). \(copy.2)")
    }
}

// MARK: Stack rows

/// The stack's number: accent when current, press to make it current.
private final class Number: Pressable {
    private let text: NSTextField

    init(_ i: Int) {
        text = label("\(i + 1)", sans(14, .semibold))
        super.init(title: "Make stack \(i + 1) current")
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        pin(self, width: 22, height: 26)
        radius = Radius.chip
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: centerXAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func render(current: Bool) {
        text.textColor = current ? Ink.accent : Ink.primary
    }

    override func restyle() { color = hovering ? Ink.primary(0.055) : nil }
}

/// A stack name, edited in place on a soft fill.
private final class NameField: NSTextField {
    let box = Fill(Ink.primary(0.055), radius: Radius.chip)

    init() {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = sans(14, .medium)
        textColor = Ink.primary
        usesSingleLineMode = true
        cell?.isScrollable = true
        placeholderString = "Name"
        translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(self)
        pin(box, width: 200, height: 30)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: Space.sm),
            trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -Space.sm),
            centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
