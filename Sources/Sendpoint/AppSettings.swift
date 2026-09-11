import AppKit
import Carbon.HIToolbox
import SendpointDomain
import Observation
import ServiceManagement

enum StackExportMode: Equatable, Sendable {
    case paste
    case copy

    init(pasteDirectly: Bool) {
        self = pasteDirectly ? .paste : .copy
    }

    var shortcutTitle: String {
        switch self {
        case .paste: "Paste stack as Markdown"
        case .copy: "Copy stack as Markdown"
        }
    }

    var shortcutDetail: String {
        switch self {
        case .paste: "Fills the template and pastes it at your cursor."
        case .copy: "Fills the template and copies it to the clipboard."
        }
    }

    /// Caption over the template options that apply once per export.
    var exportMomentCaption: String {
        switch self {
        case .paste: "When you paste"
        case .copy: "When you copy"
        }
    }

    var verb: String {
        switch self {
        case .paste: "paste"
        case .copy: "copy"
        }
    }
}

enum ShortcutSlot: String, CaseIterable, Hashable, Sendable {
    case voiceCapture
    case capture
    case copy
    case stack
    case switchSession
    case nextStack
    case previousStack
    case clear

    var title: String {
        switch self {
        case .voiceCapture: "Voice note"
        case .capture: "Typed note"
        case .copy: "Export stack as Markdown"
        case .stack: "Show stack"
        case .switchSession: "Switch stack"
        case .nextStack: "Next stack"
        case .previousStack: "Previous stack"
        case .clear: "Clear stack"
        }
    }

    /// Slots that ship unbound and may be cleared again.
    var isOptional: Bool {
        switch self {
        case .nextStack, .previousStack: true
        default: false
        }
    }
}

extension ShortcutSlot {
    /// The registered hotkey name for this shortcut slot.
    var hotKeyName: HotKeyName {
        switch self {
        case .voiceCapture: .voiceCapture
        case .capture: .capture
        case .copy: .copy
        case .stack: .stack
        case .switchSession: .switchSession
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
        case .invalid:
            "Choose a shortcut with Control, Option, or Command."
        case let .duplicate(slot):
            "That shortcut is already used by \(slot.title)."
        case let .reserved(name):
            "That shortcut is reserved for \(name)."
        }
    }
}

enum ShortcutRegistrationIssue: Equatable, Identifiable {
    case conflict(slot: ShortcutSlot, combo: KeyCombo, reason: ShortcutConflict)
    case invalid(slot: ShortcutSlot, combo: KeyCombo)
    case unavailable(slot: ShortcutSlot, combo: KeyCombo, status: Int32)

    var id: ShortcutSlot {
        switch self {
        case let .conflict(slot, _, _), let .invalid(slot, _), let .unavailable(slot, _, _):
            slot
        }
    }

    var message: String {
        switch self {
        case let .conflict(_, _, reason):
            reason.localizedDescription
        case let .invalid(slot, _):
            "\(slot.title) has an invalid shortcut. Choose another one in Settings."
        case let .unavailable(slot, combo, status):
            "\(slot.title) shortcut \(combo.displayString) is unavailable (system error \(status)). Choose another shortcut in Settings."
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let profiles = "profiles"
        static let activeProfileID = "activeProfileID"
        static let voiceMode = "voiceMode"
        static func combo(_ slot: ShortcutSlot) -> String { slot.rawValue + "Combo" }
        static let pasteDirectly = "pasteDirectly"
        static let restoreFocusAfterSave = "restoreFocusAfterSave"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceName = "inputDeviceName"
    }

    private static let defaultCombos: [ShortcutSlot: KeyCombo] = [
        .voiceCapture: KeyCombo(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command]),
        .capture: KeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [.control, .command]),
        .copy: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .command]),
        .stack: KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .command]),
        .switchSession: KeyCombo(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command]),
        .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command]),
    ]

    /// Marks an optional slot the user cleared, so the default does not return.
    private static let unboundMarker = Data()

    private let defaults: UserDefaults
    private let registerLoginItem: @MainActor () throws -> Void
    private let unregisterLoginItem: @MainActor () throws -> Void

    /// One combo per bound slot. Optional slots are absent until set.
    private var combos: [ShortcutSlot: KeyCombo]
    var voiceCaptureCombo: KeyCombo { combos[.voiceCapture]! }
    var captureCombo: KeyCombo { combos[.capture]! }
    var copyCombo: KeyCombo { combos[.copy]! }
    var stackCombo: KeyCombo { combos[.stack]! }
    var switchSessionCombo: KeyCombo { combos[.switchSession]! }
    var clearCombo: KeyCombo { combos[.clear]! }
    /// Walks backwards through the cycle: the switch shortcut plus ⇧, when
    /// the shortcut itself has no ⇧.
    var switchSessionReverseCombo: KeyCombo? { switchSessionCombo.addingShift }
    var nextStackCombo: KeyCombo? { combos[.nextStack] }
    var previousStackCombo: KeyCombo? { combos[.previousStack] }

    private(set) var voiceMode: VoiceRecordingMode

    func setVoiceMode(_ mode: VoiceRecordingMode) {
        guard mode != voiceMode else { return }
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: Key.voiceMode)
        onHotKeysChanged?()
    }

    private(set) var shortcutRegistrationIssues: [ShortcutRegistrationIssue] = []

    private var profileCollection: ProfileCollection

    var profiles: [Profile] { profileCollection.profiles }
    var activeProfileID: UUID { profileCollection.activeProfileID }
    var activeProfile: Profile { profileCollection.activeProfile }

    var stackExportMode: StackExportMode {
        StackExportMode(pasteDirectly: pasteDirectly)
    }

    var pasteDirectly: Bool { didSet { defaults.set(pasteDirectly, forKey: Key.pasteDirectly); onHotKeysChanged?() } }
    var restoreFocusAfterSave: Bool { didSet { defaults.set(restoreFocusAfterSave, forKey: Key.restoreFocusAfterSave) } }

    /// The microphone voice notes record from. `nil` follows the system default.
    /// The name is kept so the picker can still show a device that is unplugged.
    private(set) var inputDeviceUID: String?
    private(set) var inputDeviceName: String?

    func setInputDevice(uid: String?, name: String?) {
        inputDeviceUID = uid
        inputDeviceName = uid == nil ? nil : name
        defaults.set(inputDeviceUID, forKey: Key.inputDeviceUID)
        defaults.set(inputDeviceName, forKey: Key.inputDeviceName)
        onInputDeviceChanged?()
    }
    private(set) var hasCompletedSetup: Bool

    private(set) var launchAtLogin: Bool

    /// The system registration decides whether the change sticks. When it
    /// fails, the property snaps back so a bound toggle shows the real state.
    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != launchAtLogin else { return }
        do {
            if enabled { try registerLoginItem() }
            else { try unregisterLoginItem() }
            launchAtLogin = enabled
        } catch {
            NSLog("Sendpoint: login item change failed — \(error)")
            launchAtLogin = !enabled
        }
    }

    /// Called when a shortcut or direct-paste behavior changes.
    var onHotKeysChanged: (() -> Void)?
    /// Called after the active profile or stored profiles change.
    var onProfilesChanged: (() -> Void)?
    /// Called after the preferred microphone changes.
    var onInputDeviceChanged: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        registerLoginItem: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.register()
        },
        unregisterLoginItem: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.unregister()
        }
    ) {
        self.defaults = defaults
        self.registerLoginItem = registerLoginItem
        self.unregisterLoginItem = unregisterLoginItem
        combos = Self.defaultCombos.merging(
            ShortcutSlot.allCases.compactMap { slot in
                AppSettings.read(Key.combo(slot), from: defaults).map { (slot, $0) }
            },
            uniquingKeysWith: { _, stored in stored }
        )
        voiceMode = defaults.string(forKey: Key.voiceMode).flatMap(VoiceRecordingMode.init(rawValue:)) ?? .hold

        let decoded = defaults.data(forKey: Key.profiles)
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        profileCollection = ProfileCollection(
            restoring: decoded,
            activeProfileID: defaults.string(forKey: Key.activeProfileID).flatMap(UUID.init(uuidString:))
        )

        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true
        restoreFocusAfterSave = defaults.object(forKey: Key.restoreFocusAfterSave) as? Bool ?? true
        hasCompletedSetup = defaults.object(forKey: Key.hasCompletedSetup) as? Bool ?? false
        let storedInputUID = defaults.string(forKey: Key.inputDeviceUID)
        inputDeviceUID = storedInputUID
        inputDeviceName = storedInputUID == nil ? nil : defaults.string(forKey: Key.inputDeviceName)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        shortcutRegistrationIssues = ShortcutSlot.allCases.compactMap { slot in
            guard let combo = combo(for: slot) else { return nil }
            if let conflict = shortcutConflict(for: combo, excluding: slot) {
                return .conflict(slot: slot, combo: combo, reason: conflict)
            }
            guard combo.isValid else { return .invalid(slot: slot, combo: combo) }
            return nil
        }

        persistProfiles()
        persistActiveProfileID()
    }

    func completeSetup() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true
        defaults.set(true, forKey: Key.hasCompletedSetup)
    }

    func combo(for slot: ShortcutSlot) -> KeyCombo? { combos[slot] }

    /// Every key a slot takes when bound to `combo`: the combo itself, and for
    /// the switch shortcut also its ⇧ variant, which walks the cycle backwards.
    private static func claimedCombos(_ combo: KeyCombo, for slot: ShortcutSlot) -> [KeyCombo] {
        guard slot == .switchSession, let reverse = combo.addingShift else { return [combo] }
        return [combo, reverse]
    }

    func shortcutConflict(for proposed: KeyCombo, excluding slot: ShortcutSlot) -> ShortcutConflict? {
        guard proposed.isValid else { return .invalid }

        let fixed: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]), "Close Window (⌘W)"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command]), "Undo (⌘Z)"),
        ]
        let claimed = Self.claimedCombos(proposed, for: slot)
        if let (_, name) = fixed.first(where: { claimed.contains($0.0) }) {
            return .reserved(name)
        }
        if let duplicate = ShortcutSlot.allCases.first(where: { other in
            guard other != slot, let combo = combo(for: other) else { return false }
            return !Set(Self.claimedCombos(combo, for: other)).isDisjoint(with: claimed)
        }) {
            return .duplicate(duplicate)
        }
        return nil
    }

    func setShortcut(_ proposed: KeyCombo, for slot: ShortcutSlot) throws {
        if let conflict = shortcutConflict(for: proposed, excluding: slot) {
            throw conflict
        }
        combos[slot] = proposed
        persist(proposed, key: Key.combo(slot))
        onHotKeysChanged?()
    }

    /// Unbinds an optional slot. Required slots keep their shortcut.
    func clearShortcut(for slot: ShortcutSlot) {
        guard slot.isOptional, combos[slot] != nil else { return }
        combos[slot] = nil
        defaults.set(Self.unboundMarker, forKey: Key.combo(slot))
        onHotKeysChanged?()
    }

    func updateShortcutRegistrationIssues(_ issues: [ShortcutRegistrationIssue]) {
        guard shortcutRegistrationIssues != issues else { return }
        shortcutRegistrationIssues = issues
    }

    func selectProfile(id: UUID) throws {
        try changeProfiles { try $0.select(id: id) }
    }

    func updateProfile(_ profile: Profile) throws {
        try changeProfiles { try $0.update(profile) }
    }

    func addProfile(_ profile: Profile) throws {
        try changeProfiles { try $0.add(profile) }
    }

    @discardableResult
    func deleteProfile(id: UUID) throws -> UUID {
        try changeProfiles { try $0.delete(id: id) }
        return activeProfileID
    }

    func profile(id: UUID) -> Profile? {
        profileCollection.profile(id: id)
    }

    func validatedName(_ proposedName: String, excluding profileID: UUID?) throws -> String {
        try profileCollection.validatedName(proposedName, excluding: profileID)
    }

    /// Publish a valid snapshot before notifying clients. Rejected and unchanged
    /// operations neither write defaults nor notify observers.
    private func changeProfiles(_ change: (inout ProfileCollection) throws -> Void) throws {
        var candidate = profileCollection
        try change(&candidate)
        guard candidate != profileCollection else { return }
        let profilesChanged = candidate.profiles != profiles
        let selectionChanged = candidate.activeProfileID != activeProfileID
        profileCollection = candidate
        if profilesChanged { persistProfiles() }
        if selectionChanged { persistActiveProfileID() }
        onProfilesChanged?()
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Key.profiles)
    }

    private func persistActiveProfileID() {
        defaults.set(activeProfileID.uuidString, forKey: Key.activeProfileID)
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
