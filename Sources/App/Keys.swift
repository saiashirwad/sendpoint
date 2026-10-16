import AppKit
import Carbon.HIToolbox

/// The fixed global shortcuts. Change them here; there is no settings UI.
enum Key: UInt32, CaseIterable {
    case capture = 1, speak, paste, stack1, stack2, stack3, stack4

    var combo: (code: Int, modifiers: Int) {
        switch self {
        case .capture: (kVK_ANSI_G, cmdKey)
        case .speak: (kVK_ANSI_E, cmdKey)
        case .paste: (kVK_ANSI_V, cmdKey | controlKey)
        case .stack1: (kVK_ANSI_1, optionKey)
        case .stack2: (kVK_ANSI_2, optionKey)
        case .stack3: (kVK_ANSI_3, optionKey)
        case .stack4: (kVK_ANSI_4, optionKey)
        }
    }
}

enum Keys {
    nonisolated(unsafe) private static var handler: (Key, _ down: Bool) -> Void = { _, _ in }

    static func install(_ onKey: @escaping (Key, _ down: Bool) -> Void) {
        handler = onKey
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let key = Key(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { Keys.handler(key, down) }   // Carbon delivers on the main thread
            return noErr
        }, specs.count, &specs, nil, nil)

        for key in Key.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5344_5054), id: key.rawValue)   // 'SDPT'
            let status = RegisterEventHotKey(UInt32(key.combo.code), UInt32(key.combo.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status != noErr { NSLog("Sendpoint: hotkey \(key) unavailable (\(status))") }
        }
    }
}
