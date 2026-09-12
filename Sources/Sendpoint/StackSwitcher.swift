import AppKit
import Carbon.HIToolbox
import SendpointDomain

/// Owns cycling and modifier release; the existing palette owns presentation.
final class StackSwitcherController {
    private enum Lifecycle { case active, tornDown }

    private let store: StackStore
    private let settings: ShortcutSettings
    private let hotKeyCenter: HotKeyCenter
    private let showPreview: (UUID) -> Void
    private let hidePreview: () -> Void
    private let canBeginCycle: () -> Bool
    private let onOpenPalette: (UUID) -> Void
    private let onSwitched: (StackItemFacts) -> Void
    private var machine = StackSwitchMachine()
    private var releaseWatch: Task<Void, Never>?
    private var flagMonitors: [Any] = []
    private var lingerTask: Task<Void, Never>?
    private var lifecycle: Lifecycle = .active

    /// Direct next/previous shortcuts briefly show their destination.
    static let minimumVisibleDuration: TimeInterval = 0.3

    init(store: StackStore, settings: ShortcutSettings, hotKeyCenter: HotKeyCenter,
         showPreview: @escaping (UUID) -> Void,
         hidePreview: @escaping () -> Void,
         canBeginCycle: @escaping () -> Bool,
         onOpenPalette: @escaping (UUID) -> Void,
         onSwitched: @escaping (StackItemFacts) -> Void) {
        self.store = store
        self.settings = settings
        self.hotKeyCenter = hotKeyCenter
        self.showPreview = showPreview
        self.hidePreview = hidePreview
        self.canBeginCycle = canBeginCycle
        self.onOpenPalette = onOpenPalette
        self.onSwitched = onSwitched
    }

    // MARK: - Events

    func press(reverse: Bool) { send(.press(reverse: reverse)) }
    func cancel() { send(.escape) }
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
    }

    private func send(_ event: StackSwitchEvent) {
        guard lifecycle == .active else { return }
        switch event {
        case .press, .step:
            if machine.state != .cycling, !canBeginCycle() { NSSound.beep(); return }
        default: break
        }
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
        if machine.isShowingPreview, let highlight = machine.highlight { showPreview(highlight) }
        for command in commands { run(command) }
        // Resources follow the state, not the commands, so a cycle begun
        // while the last confirmation still showed is armed all the same.
        if machine.state == .cycling {
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
        case .showPreview:
            break // The highlight is projected before presentation commands run.
        case .hidePreview:
            lingerTask?.cancel()
            lingerTask = nil
            hidePreview()
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
            lingerTask?.cancel()
            lingerTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(Self.minimumVisibleDuration)) } catch { return }
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
            carbonModifiers: modifiers, pressed: { [weak self] in self?.send(.escape) })
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

}
