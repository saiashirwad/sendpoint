import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SendpointDomain

nonisolated enum ShortcutSlot: Hashable, Sendable {
    case voiceCapture, capture, dictate, copy, stack, clear, editLatest
    case selectStack(Int)

    static let allCases: [ShortcutSlot] =
        [.voiceCapture, .capture, .dictate, .copy, .stack, .clear, .editLatest] + selectStackCases
    static let selectStackCases: [ShortcutSlot] = (1...StackDocument.stackCount).map(ShortcutSlot.selectStack)

    var rawValue: String {
        switch self {
        case .voiceCapture: "voiceCapture"
        case .capture: "capture"
        case .dictate: "dictate"
        case .copy: "copy"
        case .stack: "stack"
        case .clear: "clear"
        case .editLatest: "editLatest"
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
        case .editLatest: "Edit latest note"
        case let .selectStack(number): stackTitle(number)
        }
    }

    var isOptional: Bool {
        switch self {
        case .dictate, .selectStack, .editLatest: true
        default: false
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .voiceCapture: KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: [.command])
        case .capture: KeyCombo(keyCode: UInt16(kVK_ANSI_G), modifiers: [.command])
        case .dictate: KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.option])
        case .copy: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .command])
        case .stack: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command])
        case .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command])
        case .editLatest: KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: [.control, .command])
        case let .selectStack(number):
            KeyCombo(keyCode: UInt16([kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon][number - 1]),
                     modifiers: [.option])
        }
    }

    var defaultYields: Bool {
        switch self {
        case .selectStack, .editLatest: true
        default: false
        }
    }

    func claims(_ combo: KeyCombo) -> [KeyCombo] {
        guard case .selectStack = self, let move = combo.addingShift else { return [combo] }
        return [combo, move]
    }
}

enum ShortcutPreference: Codable, Equatable {
    case `default`
    case custom(KeyCombo)
    case disabled
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

enum ShortcutConfigurationIssue: Equatable, Identifiable {
    case conflict(slot: ShortcutSlot, combo: KeyCombo, reason: ShortcutConflict)
    case invalid(slot: ShortcutSlot, combo: KeyCombo)
    case displaced(slot: ShortcutSlot, combo: KeyCombo, by: ShortcutSlot)

    var id: ShortcutSlot {
        switch self {
        case let .conflict(slot, _, _), let .invalid(slot, _),
             let .displaced(slot, _, _): slot
        }
    }

    var message: String {
        switch self {
        case let .conflict(_, _, reason): reason.localizedDescription
        case let .invalid(slot, _):
            "\(slot.title) has an invalid shortcut. Choose another one in Settings."
        case let .displaced(_, combo, owner):
            "\(combo.displayString) already belongs to \(owner.title). Choose another shortcut."
        }
    }
}

struct ShortcutRegistrationFailure: Equatable, Identifiable {
    let slot: ShortcutSlot
    let combo: KeyCombo
    let status: Int32

    var id: ShortcutSlot { slot }
    var message: String {
        "\(slot.title) shortcut \(combo.displayString) is unavailable "
            + "(system error \(status)). Choose another shortcut in Settings."
    }
}

struct ShortcutBindingPlan {
    private(set) var bindings: [ShortcutSlot: KeyCombo] = [:]
    private(set) var issues: [ShortcutConfigurationIssue] = []
    private var configured: [ShortcutSlot: KeyCombo] = [:]

    init(preferences: [ShortcutSlot: ShortcutPreference]) {
        var yielding: [(ShortcutSlot, KeyCombo)] = []
        for slot in ShortcutSlot.allCases {
            switch preferences[slot] ?? .default {
            case .default:
                if slot.defaultYields { yielding.append((slot, slot.defaultCombo)) }
                else { configured[slot] = slot.defaultCombo }
            case let .custom(combo): configured[slot] = combo
            case .disabled: break
            }
        }
        var displaced: [ShortcutSlot: ShortcutConfigurationIssue] = [:]
        for (slot, combo) in yielding {
            if case let .duplicate(owner) = conflict(for: combo, excluding: slot) {
                displaced[slot] = .displaced(slot: slot, combo: combo, by: owner)
            } else {
                configured[slot] = combo
            }
        }
        for slot in ShortcutSlot.allCases {
            if let issue = displaced[slot] { issues.append(issue) }
            guard let combo = configured[slot] else { continue }
            if !combo.isValid { issues.append(.invalid(slot: slot, combo: combo)) }
            else if let reason = conflict(for: combo, excluding: slot) {
                issues.append(.conflict(slot: slot, combo: combo, reason: reason))
            } else { bindings[slot] = combo }
        }
    }

    func configuredCombo(for slot: ShortcutSlot) -> KeyCombo? { configured[slot] }
    func moveCombo(_ number: Int) -> KeyCombo? { bindings[.selectStack(number)]?.addingShift }

    func conflict(for proposed: KeyCombo, excluding slot: ShortcutSlot) -> ShortcutConflict? {
        guard proposed.isValid else { return .invalid }
        let claims = slot.claims(proposed)
        let reserved: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]), "Close Window (⌘W)"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command]), "Undo (⌘Z)"),
        ]
        if let (_, name) = reserved.first(where: { claims.contains($0.0) }) { return .reserved(name) }
        if let owner = ShortcutSlot.allCases.first(where: { other in
            guard other != slot, let combo = configured[other] else { return false }
            return !Set(other.claims(combo)).isDisjoint(with: claims)
        }) { return .duplicate(owner) }
        return nil
    }
}

@Observable
final class ShortcutSettings {
    private let defaults: UserDefaults
    private var preferences: [ShortcutSlot: ShortcutPreference]
    private(set) var registrationFailures: [ShortcutRegistrationFailure] = []

    var bindingPlan: ShortcutBindingPlan { ShortcutBindingPlan(preferences: preferences) }
    var configurationIssues: [ShortcutConfigurationIssue] { bindingPlan.issues }

    var voiceCaptureCombo: KeyCombo? { combo(for: .voiceCapture) }
    var captureCombo: KeyCombo? { combo(for: .capture) }
    var copyCombo: KeyCombo? { combo(for: .copy) }
    var stackCombo: KeyCombo? { combo(for: .stack) }
    var clearCombo: KeyCombo? { combo(for: .clear) }
    func selectStackCombo(_ number: Int) -> KeyCombo? { combo(for: .selectStack(number)) }
    func moveNoteCombo(_ number: Int) -> KeyCombo? { bindingPlan.moveCombo(number) }
    func moveNoteStackNumber(for combo: KeyCombo) -> Int? {
        (1...StackDocument.stackCount).first { moveNoteCombo($0) == combo }
    }
    var dictateCombo: KeyCombo? { combo(for: .dictate) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = [:]
        for slot in ShortcutSlot.allCases {
            guard let data = defaults.data(forKey: Self.key(slot)),
                  let preference = try? JSONDecoder().decode(ShortcutPreference.self, from: data),
                  preference != .disabled || slot.isOptional else { continue }
            preferences[slot] = preference
        }
    }

    func preference(for slot: ShortcutSlot) -> ShortcutPreference { preferences[slot] ?? .default }
    func combo(for slot: ShortcutSlot) -> KeyCombo? { bindingPlan.bindings[slot] }

    func shortcutConflict(for proposed: KeyCombo, excluding slot: ShortcutSlot) -> ShortcutConflict? {
        bindingPlan.conflict(for: proposed, excluding: slot)
    }

    func setShortcut(_ proposed: KeyCombo, for slot: ShortcutSlot) throws {
        if let conflict = shortcutConflict(for: proposed, excluding: slot) { throw conflict }
        persist(.custom(proposed), for: slot)
    }

    func clearShortcut(for slot: ShortcutSlot) {
        guard slot.isOptional else { return }
        persist(.disabled, for: slot)
    }

    func updateRegistrationFailures(_ failures: [ShortcutRegistrationFailure]) {
        guard registrationFailures != failures else { return }
        registrationFailures = failures
    }

    private func persist(_ preference: ShortcutPreference, for slot: ShortcutSlot) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        preferences[slot] = preference
        registrationFailures = []
        defaults.set(data, forKey: Self.key(slot))
    }

    private static func key(_ slot: ShortcutSlot) -> String { slot.rawValue + "Preference" }
}
