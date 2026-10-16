import AppKit
import Carbon.HIToolbox
import Core

/// Global shortcuts. The chords come from `world.config.keys`; `bind` swaps them all at once.
enum Keys {
    nonisolated(unsafe) private static var handler: (Action, _ down: Bool) -> Void = { _, _ in }
    private static var refs: [EventHotKeyRef] = []
    /// Chords another app already owns. Shown in the menu.
    static var problems: [String] = []

    static func install(_ onKey: @escaping (Action, _ down: Bool) -> Void) {
        handler = onKey
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let action = Action(rawValue: Int(id.id) - 1) else { return OSStatus(eventNotHandledErr) }
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { Keys.handler(action, down) }   // Carbon delivers on the main thread
            return noErr
        }, specs.count, &specs, nil, nil)
    }

    static func bind(_ keys: [Shortcut?]) {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        problems = []
        for action in Action.allCases {
            guard let shortcut = keys[action.rawValue] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5344_5054), id: UInt32(action.rawValue + 1))   // 'SDPT'
            let status = RegisterEventHotKey(UInt32(shortcut.code), UInt32(shortcut.mods), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                problems.append("\(shortcutLabel(shortcut)) (\(action.name)) is taken by another app")
            }
        }
    }
}
