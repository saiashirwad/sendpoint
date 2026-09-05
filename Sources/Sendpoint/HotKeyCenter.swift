import AppKit
import Carbon.HIToolbox

enum HotKeyRegistrationResult: Equatable {
    case registered
    case invalid
    case failed(Int32)
}

/// Registers system-wide shortcuts through Carbon, which works without
/// Accessibility permission and fires even when another app is frontmost.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    typealias RegisterEvent = @MainActor (UInt32, UInt32, EventHotKeyID) -> (OSStatus, EventHotKeyRef?)

    private struct Handler {
        let pressed: () -> Void
        let released: (() -> Void)?
    }
    private var handlers: [UInt32: Handler] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private let registerEvent: RegisterEvent
    private let unregisterEvent: @MainActor (EventHotKeyRef) -> Void

    init(
        registerEvent: @escaping RegisterEvent = HotKeyCenter.liveRegisterEvent,
        unregisterEvent: @escaping @MainActor (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }
    ) {
        self.registerEvent = registerEvent
        self.unregisterEvent = unregisterEvent
    }

    /// Replaces any shortcut previously registered under `name`.
    @discardableResult
    func register(name: String, combo: KeyCombo?, released: (() -> Void)? = nil, action: @escaping () -> Void) -> HotKeyRegistrationResult {
        unregister(name: name)
        guard let combo, combo.isValid else { return .invalid }
        return registerRaw(
            name: name,
            keyCode: combo.keyCode,
            carbonModifiers: combo.carbonModifiers,
            pressed: action,
            released: released
        )
    }

    /// Registers a Carbon hotkey without requiring a KeyCombo. This is used
    /// for the temporary, modifier-free Escape cancel key.
    @discardableResult
    func registerRaw(
        name: String,
        keyCode: UInt16,
        carbonModifiers: UInt32,
        pressed: @escaping () -> Void,
        released: (() -> Void)? = nil
    ) -> HotKeyRegistrationResult {
        unregister(name: name)
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_414E), id: id) // 'CLAN'
        let (status, registeredRef) = registerEvent(UInt32(keyCode), carbonModifiers, hotKeyID)
        ref = registeredRef
        guard status == noErr, let ref else {
            Diag.log("hotkey FAILED name=\(name) keyCode=\(keyCode) carbonMods=\(carbonModifiers) status=\(status)")
            return .failed(status)
        }
        Diag.log("hotkey ok name=\(name) keyCode=\(keyCode) carbonMods=\(carbonModifiers) id=\(id)")
        handlers[id] = Handler(pressed: pressed, released: released)
        refs[id] = ref
        names[name] = id
        return .registered
    }

    func unregister(name: String) {
        guard let id = names.removeValue(forKey: name) else { return }
        if let ref = refs.removeValue(forKey: id) { unregisterEvent(ref) }
        handlers[id] = nil
    }

    private var names: [String: UInt32] = [:]

    func fire(id: UInt32, released: Bool) {
        guard let handler = handlers[id] else { return }
        Diag.log("hotkey fired id=\(id)")
        if released { handler.released?() } else { handler.pressed() }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        let pressedSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var specs = [pressedSpec, EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyReleased)
        )]
        InstallEventHandler(
            GetApplicationEventTarget(), hotKeyEventHandler,
            specs.count, &specs, nil, nil
        )
    }

    private static func liveRegisterEvent(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        hotKeyID: EventHotKeyID
    ) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        return (status, ref)
    }
}

private func hotKeyEventHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    let hotKeyID = id.id
    let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
    DispatchQueue.main.async { HotKeyCenter.shared.fire(id: hotKeyID, released: released) }
    return noErr
}
