import AppKit
import Carbon.HIToolbox
import SendpointDomain

enum HotKeyName: Hashable {
    case slot(ShortcutSlot)
    case voiceEscape

    var label: String {
        switch self {
        case let .slot(slot): slot.rawValue
        case .voiceEscape: "voiceEscape"
        }
    }
}

enum HotKeyRegistrationResult: Equatable {
    case registered
    case invalid
    case failed(Int32)
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    typealias RegisterEvent = @MainActor (UInt32, UInt32, EventHotKeyID) -> (OSStatus, EventHotKeyRef?)

    private struct Registration {
        let id: UInt32
        let ref: EventHotKeyRef
        let pressed: () -> Void
        let released: (() -> Void)?
    }
    private var registrations: [HotKeyName: Registration] = [:]
    private let registerEvent: RegisterEvent
    private let unregisterEvent: @MainActor (EventHotKeyRef) -> Void

    private final class WeakCenter {
        weak var value: HotKeyCenter?
        init(_ value: HotKeyCenter) { self.value = value }
    }

    private static var routes: [UInt32: WeakCenter] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(
        registerEvent: @escaping RegisterEvent = HotKeyCenter.liveRegisterEvent,
        unregisterEvent: @escaping @MainActor (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }
    ) {
        self.registerEvent = registerEvent
        self.unregisterEvent = unregisterEvent
    }

    @discardableResult
    func register(name: HotKeyName, combo: KeyCombo?, released: (() -> Void)? = nil, action: @escaping () -> Void) -> HotKeyRegistrationResult {
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

    @discardableResult
    func registerRaw(
        name: HotKeyName,
        keyCode: UInt16,
        carbonModifiers: UInt32,
        pressed: @escaping () -> Void,
        released: (() -> Void)? = nil
    ) -> HotKeyRegistrationResult {
        unregister(name: name)
        Self.installHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_414E), id: id)
        let (status, ref) = registerEvent(UInt32(keyCode), carbonModifiers, hotKeyID)
        guard status == noErr, let ref else {
            Diag.log("hotkey FAILED name=\(name.label) keyCode=\(keyCode) carbonMods=\(carbonModifiers) status=\(status)")
            return .failed(status)
        }
        Diag.log("hotkey ok name=\(name.label) keyCode=\(keyCode) carbonMods=\(carbonModifiers) id=\(id)")
        registrations[name] = Registration(id: id, ref: ref, pressed: pressed, released: released)
        Self.routes[id] = WeakCenter(self)
        return .registered
    }

    func unregister(name: HotKeyName) {
        guard let registration = registrations.removeValue(forKey: name) else { return }
        unregisterEvent(registration.ref)
        Self.routes.removeValue(forKey: registration.id)
    }

    func unregisterAll() {
        for name in Array(registrations.keys) { unregister(name: name) }
    }

    func fire(id: UInt32, released: Bool) {
        guard let registration = registrations.values.first(where: { $0.id == id }) else { return }
        Diag.log("hotkey fired id=\(id)")
        if released { registration.released?() } else { registration.pressed() }
    }

    static func route(id: UInt32, released: Bool) {
        guard let center = routes[id]?.value else { return }
        center.fire(id: id, released: released)
    }

    private static func installHandlerIfNeeded() {
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

nonisolated private func hotKeyEventHandler(
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
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyCenter.route(id: hotKeyID, released: released) }
    }
    return noErr
}
