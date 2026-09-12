import AppKit
import Carbon.HIToolbox
import Observation
import SendpointDomain
import SwiftUI

/// What the switcher overlay draws: the stacks being walked and the lit one.
@Observable
final class StackSwitcherModel {
    private(set) var rows: [StackItemFacts] = []
    private(set) var highlight: UUID?
    private(set) var visible = false

    func show(rows: [StackItemFacts], highlight: UUID?) {
        self.rows = rows
        self.highlight = highlight
        visible = true
    }

    func hide() {
        visible = false
    }
}

/// Owns the ⌘Tab-style stack switcher: the hotkey presses, the watch for the
/// modifiers coming up, the temporary Escape and arrow keys that only exist
/// while cycling, the overlay panel, and the switch itself. One teardown
/// path releases all of it.
final class StackSwitcherController {
    private enum Lifecycle { case active, tornDown }

    private let store: StackStore
    private let settings: ShortcutSettings
    private let hotKeyCenter: HotKeyCenter
    private let surfaces: SurfaceCoordinator
    private let onOpenPalette: (UUID) -> Void
    private let onSwitched: (StackItemFacts) -> Void
    private var machine = StackSwitchMachine()
    private let model = StackSwitcherModel()
    private var panel: NSPanel?
    private var releaseWatch: Task<Void, Never>?
    private var flagMonitors: [Any] = []
    private var lingerTask: Task<Void, Never>?
    private var cycleStartedAt: CFAbsoluteTime?
    private var lifecycle: Lifecycle = .active

    /// A quick tap shows the strip for at least this long in total, so the
    /// chosen stack can be read. A hold that already lasted this long has
    /// been seen, and the strip goes the instant the keys come up.
    static let minimumVisibleDuration: TimeInterval = 0.3

    init(store: StackStore, settings: ShortcutSettings, hotKeyCenter: HotKeyCenter,
         surfaces: SurfaceCoordinator,
         onOpenPalette: @escaping (UUID) -> Void,
         onSwitched: @escaping (StackItemFacts) -> Void) {
        self.store = store
        self.settings = settings
        self.hotKeyCenter = hotKeyCenter
        self.surfaces = surfaces
        self.onOpenPalette = onOpenPalette
        self.onSwitched = onSwitched
        // Built now, while nobody is waiting: a window plus a SwiftUI hosting
        // view costs tens of milliseconds, which must not sit between the
        // key and the strip.
        panel = makePanel()
        surfaces.register(.switcher, transitions: .init(
            show: { [weak self] in self?.presentOverlay() },
            hide: { [weak self] in self?.hideOverlay() }
        ))
    }

    // MARK: - Events

    func press(reverse: Bool) { send(.press(reverse: reverse)) }
    func step(_ offset: Int) { send(.step(offset)) }
    func documentChanged() { send(.ordersChanged) }

    func teardown() {
        guard lifecycle == .active else { return }
        send(.teardown)
        surfaces.unregister(.switcher)
        stopReleaseWatch()
        unregisterTemporaryKeys()
        lingerTask?.cancel()
        lingerTask = nil
        lifecycle = .tornDown
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func send(_ event: StackSwitchEvent) {
        guard lifecycle == .active else { return }
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            if elapsed > 4 { Diag.log("switcher \(event) took \(Int(elapsed))ms") }
        }
        let orders = StackSwitchOrders(
            recent: store.stacksByRecency.map(\.id),
            listed: store.stacks.map(\.id)
        )
        let commands = machine.handle(event, orders: orders)
        // The rows go in before the overlay is shown, so it is sized for them.
        if machine.isShowingOverlay { model.show(rows: rows(for: machine.order), highlight: machine.highlight) }
        for command in commands { run(command) }
        // Resources follow the state, not the commands, so a cycle begun
        // while the last confirmation still showed is armed all the same.
        if machine.state == .cycling {
            if cycleStartedAt == nil { cycleStartedAt = CFAbsoluteTimeGetCurrent() }
            lingerTask?.cancel()
            lingerTask = nil
            startReleaseWatch()
            registerTemporaryKeys()
        } else {
            stopReleaseWatch()
            unregisterTemporaryKeys()
        }
    }

    private func run(_ command: StackSwitchCommand) {
        switch command {
        case .showOverlay:
            surfaces.present(.switcher)
        case .hideOverlay:
            lingerTask?.cancel()
            lingerTask = nil
            model.hide()
            surfaces.dismiss(.switcher)
        case let .switchTo(id):
            store.mutate(.switchStack(stackID: id)) { [weak self] outcome in
                guard let self, self.lifecycle == .active else { return }
                switch outcome {
                case .committed, .noOp:
                    if let facts = self.facts.stack(id: id) { self.onSwitched(facts) }
                case .rejected, .commitFailed, .cancelled:
                    NSSound.beep()
                }
            }
        case let .openPalette(id):
            onOpenPalette(id)
        case .startLinger:
            let shown = cycleStartedAt.map { CFAbsoluteTimeGetCurrent() - $0 } ?? 0
            cycleStartedAt = nil
            let remaining = Self.minimumVisibleDuration - shown
            lingerTask?.cancel()
            guard remaining > 0.01 else {
                send(.lingerElapsed)
                return
            }
            lingerTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.lingerTask = nil
                self.send(.lingerElapsed)
            }
        case .beep:
            NSSound.beep()
        }
    }

    // MARK: - Facts

    private var facts: StackUIFacts { StackUIFacts(store: store) }

    private func rows(for order: [UUID]) -> [StackItemFacts] {
        let facts = facts
        return order.compactMap { facts.stack(id: $0) }
    }

    // MARK: - Release detection

    private var watchedModifiers: NSEvent.ModifierFlags {
        settings.switchStackCombo.modifiers.intersection([.command, .option, .control])
    }

    /// The moment every modifier of the switch shortcut is up, the lit stack
    /// is chosen. Modifier-change events deliver that instant; they need the
    /// Accessibility grant the app already has for reading selections, so a
    /// poll of the hardware modifier state, which needs nothing, backs them.
    private func startReleaseWatch() {
        guard releaseWatch == nil else { return }
        let watched = watchedModifiers
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.intersection(watched).isEmpty else { return }
            MainActor.assumeIsolated { self?.send(.release) }
        }
        flagMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { handler($0); return $0 },
        ].compactMap { $0 }
        releaseWatch = Task { [weak self] in
            while !Task.isCancelled {
                if NSEvent.modifierFlags.intersection(watched).isEmpty {
                    guard let self, !Task.isCancelled else { return }
                    self.send(.release)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
            }
        }
    }

    private func stopReleaseWatch() {
        releaseWatch?.cancel()
        releaseWatch = nil
        flagMonitors.forEach { NSEvent.removeMonitor($0) }
        flagMonitors = []
    }

    // MARK: - Temporary keys

    /// While cycling, Escape cancels and an arrow pins the full palette. The
    /// arrows carry the shortcut's modifiers, since those are still held, and
    /// a Carbon registration swallows them so the front app never sees ⌘↓.
    private var temporaryKeysRegistered = false

    private func registerTemporaryKeys() {
        guard !temporaryKeysRegistered else { return }
        temporaryKeysRegistered = true
        let modifiers = settings.switchStackCombo.carbonModifiers
        hotKeyCenter.registerRaw(name: .switchEscape, keyCode: UInt16(kVK_Escape),
            carbonModifiers: 0, pressed: { [weak self] in self?.send(.escape) })
        hotKeyCenter.registerRaw(name: .switchPinUp, keyCode: UInt16(kVK_UpArrow),
            carbonModifiers: modifiers, pressed: { [weak self] in self?.send(.pin) })
        hotKeyCenter.registerRaw(name: .switchPinDown, keyCode: UInt16(kVK_DownArrow),
            carbonModifiers: modifiers, pressed: { [weak self] in self?.send(.pin) })
    }

    private func unregisterTemporaryKeys() {
        guard temporaryKeysRegistered else { return }
        temporaryKeysRegistered = false
        for name in [HotKeyName.switchEscape, .switchPinUp, .switchPinDown] {
            hotKeyCenter.unregister(name: name)
        }
    }

    // MARK: - Overlay

    private func presentOverlay() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        // Ordering front does not draw; force the frame now so the strip is
        // on screen this run of the loop, not after SwiftUI's next tick.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    private func hideOverlay() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        Self.makePanel(model: model)
    }

    static func makePanel(model: StackSwitcherModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: StackSwitcherView.width, height: 200),
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
        let hosting = NSHostingView(rootView: StackSwitcherView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        return panel
    }

    /// Centred on the screen with the pointer, a little above the middle,
    /// where ⌘⇥ puts its own strip.
    private func place(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = StackSwitcherView.size(rows: model.rows.count)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08
        ))
    }
}

/// A compact stack list with the palette's row highlight and selection rule.
struct StackSwitcherView: View {
    let model: StackSwitcherModel
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 300
    private static let rowHeight: CGFloat = 36
    private static let maximumVisibleRows = 6
    private static let inset: CGFloat = 8
    /// Room for the shadow around the sheet.
    private static let margin: CGFloat = 32

    private static func listHeight(rows: Int) -> CGFloat {
        CGFloat(min(max(rows, 1), maximumVisibleRows)) * rowHeight
    }

    /// Size the panel before SwiftUI lays it out, including long stack lists.
    static func size(rows: Int) -> CGSize {
        CGSize(width: width + margin * 2,
               height: listHeight(rows: rows) + inset * 2 + margin * 2)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { position, row in
                        let lit = row.id == model.highlight
                        StackRow(noteCount: row.noteCount, position: position, showsDigit: false) {
                            Text(row.name)
                                .font(.system(size: 14, weight: lit ? .medium : .regular))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: Self.rowHeight)
                        .background(lit ? PaletteTint.selection : Color.clear)
                        .overlay(alignment: .leading) {
                            if lit {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.65))
                                    .frame(width: 3)
                            }
                        }
                        .animation(.easeOut(duration: 0.06), value: lit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.name + (lit ? ", chosen" : "") + (row.isCurrent ? ", current" : ""))
                        .accessibilityValue(row.countLabel)
                        .id(row.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: Self.listHeight(rows: model.rows.count))
            .onAppear { revealSelection(using: proxy) }
            .onChange(of: model.highlight) { revealSelection(using: proxy) }
            .onChange(of: model.rows.map(\.id)) { revealSelection(using: proxy) }
        }
        .padding(.vertical, Self.inset)
        .frame(width: Self.width)
        .background(PaletteTint.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 22, y: 10)
        .opacity(model.visible ? 1 : 0)
        .animation(nil, value: model.visible)
        .padding(Self.margin)
        .fixedSize()
    }

    private func revealSelection(using proxy: ScrollViewProxy) {
        guard let highlight = model.highlight else { return }
        proxy.scrollTo(highlight)
    }
}
