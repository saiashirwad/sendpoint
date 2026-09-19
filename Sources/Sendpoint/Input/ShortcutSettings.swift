import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SendpointDomain

nonisolated enum ShortcutSlot: Hashable, Sendable {
    case voiceCapture, capture, dictate, copy, stack, clear
    case selectStack(Int)

    static let allCases: [ShortcutSlot] =
        [.voiceCapture, .capture, .dictate, .copy, .stack, .clear] + selectStackCases
    static let selectStackCases: [ShortcutSlot] = (1...StackDocument.stackCount).map(ShortcutSlot.selectStack)

    var rawValue: String {
        switch self {
        case .voiceCapture: "voiceCapture"
        case .capture: "capture"
        case .dictate: "dictate"
        case .copy: "copy"
        case .stack: "stack"
        case .clear: "clear"
        case let .selectStack(number): "selectStack\(number)"
        }
    }

    var title: String {
        switch self {
        case .voiceCapture: "Voice note"
        case .capture: "Typed note"
        case .dictate: "Dictate"
        case .copy: "Export stack as Markdown"
        case .stack: "Show stack"
        case .clear: "Clear stack"
        case let .selectStack(number): stackTitle(number)
        }
    }

    var isOptional: Bool {
        switch self {
        case .dictate, .selectStack: true
        default: false
        }
    }
}

enum ShortcutConflict: Error, Equatable, LocalizedError {
    case invalid
    case duplicate(ShortcutSlot)
    case reserved(String)

    var errorDescription: String? {
        switch self {
        case .invalid: "Choose a shortcut with Control, Option, or Command."
        case let .duplicate(slot): "That shortcut is already used by \(slot.title)."
        case let .reserved(name): "That shortcut is reserved for \(name)."
        }
    }
}

enum ShortcutRegistrationIssue: Equatable, Identifiable {
    case conflict(slot: ShortcutSlot, combo: KeyCombo, reason: ShortcutConflict)
    case invalid(slot: ShortcutSlot, combo: KeyCombo)
    case unavailable(slot: ShortcutSlot, combo: KeyCombo, status: Int32)
    case displaced(slot: ShortcutSlot, combo: KeyCombo, by: ShortcutSlot)

    var id: ShortcutSlot {
        switch self {
        case let .conflict(slot, _, _), let .invalid(slot, _), let .unavailable(slot, _, _),
             let .displaced(slot, _, _): slot
        }
    }

    var message: String {
        switch self {
        case let .conflict(_, _, reason): reason.localizedDescription
        case let .invalid(slot, _):
            "\(slot.title) has an invalid shortcut. Choose another one in Settings."
        case let .unavailable(slot, combo, status):
            "\(slot.title) shortcut \(combo.displayString) is unavailable "
                + "(system error \(status)). Choose another shortcut in Settings."
        case let .displaced(_, combo, owner):
            "\(combo.displayString) already belongs to \(owner.title). Choose another shortcut."
        }
    }
}

@Observable
final class ShortcutSettings {
    private enum Key {
        static func combo(_ slot: ShortcutSlot) -> String { slot.rawValue + "Combo" }
    }

    private static let homeRow = [kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon]

    private static let stackDefaultCombos: [(ShortcutSlot, KeyCombo)] =
        zip(ShortcutSlot.selectStackCases, homeRow).map { slot, key in
            (slot, KeyCombo(keyCode: UInt16(key), modifiers: [.option]))
        }

    private static let fixedDefaultCombos: [ShortcutSlot: KeyCombo] = [
        .voiceCapture: KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: [.command]),
        .capture: KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifiers: [.command]),
        .dictate: KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option]),
        .copy: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .command]),
        .stack: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command]),
        .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command]),
    ]
    private static let unboundMarker = Data()

    private let defaults: UserDefaults
    private var combos: [ShortcutSlot: KeyCombo]
    private var unsetStackSlots: Set<ShortcutSlot> = []
    private(set) var shortcutRegistrationIssues: [ShortcutRegistrationIssue] = []

    var voiceCaptureCombo: KeyCombo { requiredCombo(.voiceCapture) }
    var captureCombo: KeyCombo { requiredCombo(.capture) }
    var copyCombo: KeyCombo { requiredCombo(.copy) }
    var stackCombo: KeyCombo { requiredCombo(.stack) }
    var clearCombo: KeyCombo { requiredCombo(.clear) }
    func selectStackCombo(_ number: Int) -> KeyCombo? { combos[.selectStack(number)] }
    func moveNoteCombo(_ number: Int) -> KeyCombo? { selectStackCombo(number)?.addingShift }
    func moveNoteStackNumber(for combo: KeyCombo) -> Int? {
        (1...StackDocument.stackCount).first { moveNoteCombo($0) == combo }
    }
    var dictateCombo: KeyCombo? { combos[.dictate] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combos = Self.fixedDefaultCombos
        for slot in ShortcutSlot.allCases {
            switch Self.read(Key.combo(slot), from: defaults) {
            case .absent: if case .selectStack = slot { unsetStackSlots.insert(slot) }
            case .unbound: combos[slot] = nil
            case let .combo(combo): combos[slot] = combo
            }
        }
        adoptFreeStackDefaults()
        shortcutRegistrationIssues = ShortcutSlot.allCases.compactMap { slot in
            guard let combo = combos[slot] else { return displacedDefault(for: slot) }
            if let conflict = shortcutConflict(for: combo, excluding: slot) {
                return .conflict(slot: slot, combo: combo, reason: conflict)
            }
            return combo.isValid ? nil : .invalid(slot: slot, combo: combo)
        }
    }

    func combo(for slot: ShortcutSlot) -> KeyCombo? { combos[slot] }
    func displacedDefault(for slot: ShortcutSlot) -> ShortcutRegistrationIssue? {
        guard unsetStackSlots.contains(slot), combos[slot] == nil,
              let combo = Self.stackDefaultCombos.first(where: { $0.0 == slot })?.1,
              case let .duplicate(owner) = shortcutConflict(for: combo, excluding: slot)
        else { return nil }
        return .displaced(slot: slot, combo: combo, by: owner)
    }

    func shortcutConflict(for proposed: KeyCombo, excluding slot: ShortcutSlot) -> ShortcutConflict? {
        guard proposed.isValid else { return .invalid }
        let fixed: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]), "Close Window (⌘W)"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command]), "Undo (⌘Z)"),
        ]
        let claimed = Self.claimedCombos(proposed, for: slot)
        if let (_, name) = fixed.first(where: { claimed.contains($0.0) }) { return .reserved(name) }
        if let duplicate = ShortcutSlot.allCases.first(where: { other in
            guard other != slot, let combo = combo(for: other) else { return false }
            return !Set(Self.claimedCombos(combo, for: other)).isDisjoint(with: claimed)
        }) {
            return .duplicate(duplicate)
        }
        return nil
    }

    func setShortcut(_ proposed: KeyCombo, for slot: ShortcutSlot) throws {
        if let conflict = shortcutConflict(for: proposed, excluding: slot) { throw conflict }
        combos[slot] = proposed
        unsetStackSlots.remove(slot)
        persist(proposed, key: Key.combo(slot))
        adoptFreeStackDefaults()
    }

    func clearShortcut(for slot: ShortcutSlot) {
        guard slot.isOptional, combos[slot] != nil || unsetStackSlots.contains(slot) else { return }
        combos[slot] = nil
        unsetStackSlots.remove(slot)
        defaults.set(Self.unboundMarker, forKey: Key.combo(slot))
        adoptFreeStackDefaults()
    }

    private func adoptFreeStackDefaults() {
        for (slot, combo) in Self.stackDefaultCombos
        where unsetStackSlots.contains(slot) && combos[slot] == nil
            && shortcutConflict(for: combo, excluding: slot) == nil {
            combos[slot] = combo
        }
    }

    func updateShortcutRegistrationIssues(_ issues: [ShortcutRegistrationIssue]) {
        guard shortcutRegistrationIssues != issues else { return }
        shortcutRegistrationIssues = issues
    }

    private func requiredCombo(_ slot: ShortcutSlot) -> KeyCombo {
        if let combo = combos[slot] { return combo }
        guard let fallback = Self.fixedDefaultCombos[slot] else {
            preconditionFailure("Optional shortcuts have no required value")
        }
        return fallback
    }

    private static func claimedCombos(_ combo: KeyCombo, for slot: ShortcutSlot) -> [KeyCombo] {
        guard case .selectStack = slot, let move = combo.addingShift else { return [combo] }
        return [combo, move]
    }

    private func persist(_ combo: KeyCombo, key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }

    private enum Stored {
        case absent, unbound, combo(KeyCombo)
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> Stored {
        guard let data = defaults.data(forKey: key) else { return .absent }
        if data == unboundMarker { return .unbound }
        guard let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return .absent }
        return .combo(combo)
    }
}
