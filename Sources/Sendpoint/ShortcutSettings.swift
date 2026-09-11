import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

nonisolated enum ShortcutSlot: String, CaseIterable, Hashable, Sendable {
    case voiceCapture, capture, copy, stack, switchStack, nextStack, previousStack, clear

    var title: String {
        switch self {
        case .voiceCapture: "Voice note"
        case .capture: "Typed note"
        case .copy: "Export stack as Markdown"
        case .stack: "Show stack"
        case .switchStack: "Switch stack"
        case .nextStack: "Next stack"
        case .previousStack: "Previous stack"
        case .clear: "Clear stack"
        }
    }

    var isOptional: Bool {
        switch self {
        case .nextStack, .previousStack: true
        default: false
        }
    }

    var hotKeyName: HotKeyName {
        switch self {
        case .voiceCapture: .voiceCapture
        case .capture: .capture
        case .copy: .copy
        case .stack: .stack
        case .switchStack: .switchStack
        case .nextStack: .nextStack
        case .previousStack: .previousStack
        case .clear: .clear
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

    var id: ShortcutSlot {
        switch self {
        case let .conflict(slot, _, _), let .invalid(slot, _), let .unavailable(slot, _, _): slot
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
        }
    }
}

@Observable
final class ShortcutSettings {
    private enum Key {
        static func combo(_ slot: ShortcutSlot) -> String { slot.rawValue + "Combo" }
    }

    private static let defaultCombos: [ShortcutSlot: KeyCombo] = [
        .voiceCapture: KeyCombo(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command]),
        .capture: KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.control, .command]),
        .copy: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .command]),
        .stack: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command]),
        .switchStack: KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command]),
        .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command]),
    ]
    private static let unboundMarker = Data()

    private let defaults: UserDefaults
    private var combos: [ShortcutSlot: KeyCombo]
    private(set) var shortcutRegistrationIssues: [ShortcutRegistrationIssue] = []

    var voiceCaptureCombo: KeyCombo { requiredCombo(.voiceCapture) }
    var captureCombo: KeyCombo { requiredCombo(.capture) }
    var copyCombo: KeyCombo { requiredCombo(.copy) }
    var stackCombo: KeyCombo { requiredCombo(.stack) }
    var switchStackCombo: KeyCombo { requiredCombo(.switchStack) }
    var clearCombo: KeyCombo { requiredCombo(.clear) }
    var switchStackReverseCombo: KeyCombo? { switchStackCombo.addingShift }
    var nextStackCombo: KeyCombo? { combos[.nextStack] }
    var previousStackCombo: KeyCombo? { combos[.previousStack] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combos = Self.defaultCombos.merging(
            ShortcutSlot.allCases.compactMap { slot in
                Self.read(Key.combo(slot), from: defaults).map { (slot, $0) }
            },
            uniquingKeysWith: { _, stored in stored }
        )
        shortcutRegistrationIssues = ShortcutSlot.allCases.compactMap { slot in
            guard let combo = combos[slot] else { return nil }
            if let conflict = shortcutConflict(for: combo, excluding: slot) {
                return .conflict(slot: slot, combo: combo, reason: conflict)
            }
            return combo.isValid ? nil : .invalid(slot: slot, combo: combo)
        }
    }

    func combo(for slot: ShortcutSlot) -> KeyCombo? { combos[slot] }

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
        persist(proposed, key: Key.combo(slot))
    }

    func clearShortcut(for slot: ShortcutSlot) {
        guard slot.isOptional, combos[slot] != nil else { return }
        combos[slot] = nil
        defaults.set(Self.unboundMarker, forKey: Key.combo(slot))
    }

    func updateShortcutRegistrationIssues(_ issues: [ShortcutRegistrationIssue]) {
        guard shortcutRegistrationIssues != issues else { return }
        shortcutRegistrationIssues = issues
    }

    private func requiredCombo(_ slot: ShortcutSlot) -> KeyCombo {
        if let combo = combos[slot] { return combo }
        return switch slot {
        case .voiceCapture: KeyCombo(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command])
        case .capture: KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.control, .command])
        case .copy: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .command])
        case .stack: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command])
        case .switchStack: KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command])
        case .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command])
        case .nextStack, .previousStack:
            preconditionFailure("Optional shortcuts have no required value")
        }
    }

    private static func claimedCombos(_ combo: KeyCombo, for slot: ShortcutSlot) -> [KeyCombo] {
        guard slot == .switchStack, let reverse = combo.addingShift else { return [combo] }
        return [combo, reverse]
    }

    private func persist(_ combo: KeyCombo, key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: key), data != unboundMarker else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}
