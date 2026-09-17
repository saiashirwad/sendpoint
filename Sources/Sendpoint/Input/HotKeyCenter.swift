import AppKit
import Carbon.HIToolbox
import SendpointDomain

enum HotKeyName: Hashable {
    case voiceCapture
    case capture
    case dictate
    case copy
    case stack
    case clear
    case selectStack(Int)
    case voiceEscape

    static let allCases: [HotKeyName] =
        [.voiceCapture, .capture, .dictate, .copy, .stack, .clear, .voiceEscape]
        + (1...StackDocument.stackCount).map(HotKeyName.selectStack)

    var rawValue: String {
        switch self {
        case .voiceCapture: "voiceCapture"
        case .capture: "capture"
        case .dictate: "dictate"
        case .copy: "copy"
        case .stack: "stack"
        case .clear: "clear"
        case let .selectStack(number): "selectStack\(number)"
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

    private struct Handler {
        let pressed: () -> Void
        let released: (() -> Void)?
    }
    private var handlers: [UInt32: Handler] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var names: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private let registerEvent: RegisterEvent
    private let unregisterEvent: @MainActor (EventHotKeyRef) -> Void

    private final class WeakCenter {
        weak var value: HotKeyCenter?
        init(_ value: HotKeyCenter) { self.value = value }
    }

    private static var routes: [UInt32: WeakCenter] = [:]

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
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_414E), id: id)
        let (status, ref) = registerEvent(UInt32(keyCode), carbonModifiers, hotKeyID)
        guard status == noErr, let ref else {
            Diag.log("hotkey FAILED name=\(name.rawValue) keyCode=\(keyCode) carbonMods=\(carbonModifiers) status=\(status)")
            return .failed(status)
        }
        Diag.log("hotkey ok name=\(name.rawValue) keyCode=\(keyCode) carbonMods=\(carbonModifiers) id=\(id)")
        handlers[id] = Handler(pressed: pressed, released: released)
        refs[id] = ref
        names[name.rawValue] = id
        Self.routes[id] = WeakCenter(self)
        return .registered
    }

    func unregister(name: HotKeyName) {
        guard let id = names.removeValue(forKey: name.rawValue) else { return }
        if let ref = refs.removeValue(forKey: id) { unregisterEvent(ref) }
        handlers[id] = nil
        if Self.routes[id]?.value === self { Self.routes.removeValue(forKey: id) }
    }

    func fire(id: UInt32, released: Bool) {
        guard let handler = handlers[id] else { return }
        Diag.log("hotkey fired id=\(id)")
        if released { handler.released?() } else { handler.pressed() }
    }

    static func route(id: UInt32, released: Bool) {
        guard let center = routes[id]?.value else { return }
        center.fire(id: id, released: released)
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
