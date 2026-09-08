import AppKit
import Carbon.HIToolbox
import Observation
import SendpointDomain
import SwiftUI

/// What the switcher overlay draws: the stacks being walked and the lit one.
@MainActor
@Observable
final class StackSwitcherModel {
    private(set) var rows: [SessionItemFacts] = []
    private(set) var highlight: UUID?
    private(set) var visible = false

    func show(rows: [SessionItemFacts], highlight: UUID?) {
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
@MainActor
final class StackSwitcherController {
    private enum Lifecycle { case active, tornDown }
    private enum TemporaryKey: String, CaseIterable {
        case escape = "switchEscape", pinUp = "switchPinUp", pinDown = "switchPinDown"
    }

    private let store: AnnotationStore
    private let settings: AppSettings
    private let onOpenPalette: (UUID) -> Void
    private let onSwitched: (SessionItemFacts) -> Void
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

    init(store: AnnotationStore, settings: AppSettings,
         onOpenPalette: @escaping (UUID) -> Void,
         onSwitched: @escaping (SessionItemFacts) -> Void) {
        self.store = store
        self.settings = settings
        self.onOpenPalette = onOpenPalette
        self.onSwitched = onSwitched
        // Built now, while nobody is waiting: a window plus a SwiftUI hosting
        // view costs tens of milliseconds, which must not sit between the
        // key and the strip.
        panel = makePanel()
    }

    // MARK: - Events

    func press(reverse: Bool) { send(.press(reverse: reverse)) }
    func step(_ offset: Int) { send(.step(offset)) }
    func documentChanged() { send(.ordersChanged) }

    func teardown() {
        guard lifecycle == .active else { return }
        send(.teardown)
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
            recent: store.sessionsByRecency.map(\.id),
            listed: store.sessions.map(\.id)
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
            presentOverlay()
        case .hideOverlay:
            lingerTask?.cancel()
            lingerTask = nil
            model.hide()
            panel?.orderOut(nil)
        case let .switchTo(id):
            store.mutate(.switchSession(sessionID: id)) { [weak self] outcome in
                guard let self, self.lifecycle == .active else { return }
                switch outcome {
                case .committed, .noOp:
                    if let facts = self.facts.session(id: id) { self.onSwitched(facts) }
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

    private var facts: SessionUIFacts {
        SessionUIFacts(sessions: store.sessions, currentSessionID: store.currentSessionID,
            lastCleared: store.lastCleared)
    }

    private func rows(for order: [UUID]) -> [SessionItemFacts] {
        let facts = facts
        return order.compactMap { facts.session(id: $0) }
    }

    // MARK: - Release detection

    private var watchedModifiers: NSEvent.ModifierFlags {
        settings.switchSessionCombo.modifiers.intersection([.command, .option, .control])
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
        let modifiers = settings.switchSessionCombo.carbonModifiers
        HotKeyCenter.shared.registerRaw(name: TemporaryKey.escape.rawValue, keyCode: UInt16(kVK_Escape),
            carbonModifiers: 0, pressed: { [weak self] in self?.send(.escape) })
        HotKeyCenter.shared.registerRaw(name: TemporaryKey.pinUp.rawValue, keyCode: UInt16(kVK_UpArrow),
            carbonModifiers: modifiers, pressed: { [weak self] in self?.send(.pin) })
        HotKeyCenter.shared.registerRaw(name: TemporaryKey.pinDown.rawValue, keyCode: UInt16(kVK_DownArrow),
            carbonModifiers: modifiers, pressed: { [weak self] in self?.send(.pin) })
    }

    private func unregisterTemporaryKeys() {
        guard temporaryKeysRegistered else { return }
        temporaryKeysRegistered = false
        for key in TemporaryKey.allCases { HotKeyCenter.shared.unregister(name: key.rawValue) }
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

    private func makePanel() -> NSPanel {
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

/// The switcher strip, drawn in the stack palette's own language: the same
/// solid sheet, rim, row wash and type, so it reads as the palette's compact
/// form rather than a different surface. Every stack in the order being
/// walked, the lit one washed, each with its note count.
struct StackSwitcherView: View {
    let model: StackSwitcherModel
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 320
    private static let rowHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 0
    private static let inset: CGFloat = 8
    private static let footerHeight: CGFloat = 34
    /// Room for the shadow around the sheet.
    private static let margin: CGFloat = 32

    /// The hosting size for a strip of `rows` stacks, computed rather than
    /// measured so the panel is right before SwiftUI has laid anything out.
    static func size(rows: Int) -> CGSize {
        let count = CGFloat(max(rows, 1))
        let list = count * rowHeight + (count - 1) * rowSpacing + inset * 2
        return CGSize(width: width + margin * 2, height: list + footerHeight + margin * 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { position, row in
                    let lit = row.id == model.highlight
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(.system(size: 14, weight: row.isCurrent ? .semibold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if position < 9 {
                            Text("⌘\(position + 1)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .opacity(lit ? 1 : 0.7)
                        }
                        Text("\(row.annotationCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(row.annotationCount == 0
                                ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
                            .frame(minWidth: 18, alignment: .trailing)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(lit ? PaletteTint.selection : Color.clear)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name + (lit ? ", chosen" : "") + (row.isCurrent ? ", current" : ""))
                    .accessibilityValue(row.countLabel)
                }
            }
            .padding(Self.inset)
            Divider()
            HStack(spacing: 0) {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.footerHeight)
        }
        .frame(width: Self.width)
        .background(PaletteTint.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PaletteTint.cornerRadius, style: .continuous)
                .strokeBorder(PaletteTint.rim(colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 22, y: 10)
        // Appears at once, like ⌘⇥; only the highlight glides.
        .opacity(model.visible ? 1 : 0)
        .animation(nil, value: model.visible)
        .animation(.easeOut(duration: 0.06), value: model.highlight)
        .padding(Self.margin)
        .fixedSize()
    }

    /// The palette footer's cadence: what is chosen, then the keys.
    private var footer: String {
        let chosen = model.rows.first { $0.id == model.highlight }
        let lead = chosen.map { "\($0.name) · \($0.countLabel)" } ?? "Stacks"
        return "\(lead) · let go to switch · ↑↓ all stacks · ⎋ cancel"
    }
}
