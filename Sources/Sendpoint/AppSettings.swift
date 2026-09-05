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
    case clear

    var title: String {
        switch self {
        case .voiceCapture: "Voice note"
        case .capture: "Typed note"
        case .copy: "Export stack as Markdown"
        case .stack: "Show stack"
        case .switchSession: "Switch stack"
        case .clear: "Clear stack"
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

enum ProfileMutationError: Error, Equatable, LocalizedError {
    case unknownProfile
    case lastProfile
    case emptyName
    case duplicateName
    case unsavedChanges

    var errorDescription: String? {
        switch self {
        case .unknownProfile:
            return "That template no longer exists."
        case .lastProfile:
            return "The last template cannot be deleted."
        case .emptyName:
            return "Enter a template name."
        case .duplicateName:
            return "A template with that name already exists."
        case .unsavedChanges:
            return "Save or discard the template changes first."
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
        .switchSession: KeyCombo(keyCode: UInt16(kVK_ANSI_K), modifiers: [.control, .command]),
        .clear: KeyCombo(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command]),
    ]

    private let defaults: UserDefaults

    /// One combo per slot, filled in by `init`.
    private var combos: [ShortcutSlot: KeyCombo]
    var voiceCaptureCombo: KeyCombo { combo(for: .voiceCapture) }
    var captureCombo: KeyCombo { combo(for: .capture) }
    var copyCombo: KeyCombo { combo(for: .copy) }
    var stackCombo: KeyCombo { combo(for: .stack) }
    var switchSessionCombo: KeyCombo { combo(for: .switchSession) }
    var clearCombo: KeyCombo { combo(for: .clear) }

    private(set) var voiceMode: VoiceRecordingMode

    func setVoiceMode(_ mode: VoiceRecordingMode) {
        guard mode != voiceMode else { return }
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: Key.voiceMode)
        onHotKeysChanged?()
    }

    private(set) var shortcutRegistrationIssues: [ShortcutRegistrationIssue] = []

    private(set) var profiles: [Profile]
    private(set) var activeProfileID: UUID

    var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

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

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Sendpoint: login item change failed — \(error)")
            }
        }
    }

    /// Called when a shortcut or direct-paste behavior changes.
    var onHotKeysChanged: (() -> Void)?
    /// Called after the active profile or stored profiles change.
    var onProfilesChanged: (() -> Void)?
    /// Called after the preferred microphone changes.
    var onInputDeviceChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        combos = Self.defaultCombos.merging(
            ShortcutSlot.allCases.compactMap { slot in
                AppSettings.read(Key.combo(slot), from: defaults).map { (slot, $0) }
            },
            uniquingKeysWith: { _, stored in stored }
        )
        voiceMode = defaults.string(forKey: Key.voiceMode).flatMap(VoiceRecordingMode.init(rawValue:)) ?? .hold

        let decoded = defaults.data(forKey: Key.profiles)
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
        let storedProfiles = AppSettings.validProfiles(decoded)
        let loadedProfiles = storedProfiles.map(AppSettings.builtInsFirst) ?? Profile.builtIns
        let loadedStoredProfiles = storedProfiles != nil
        profiles = loadedProfiles

        let requestedID = loadedStoredProfiles
            ? defaults.string(forKey: Key.activeProfileID).flatMap(UUID.init(uuidString:))
            : nil
        activeProfileID = requestedID.flatMap { requested in
            loadedProfiles.contains(where: { $0.id == requested }) ? requested : nil
        } ?? loadedProfiles[0].id

        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true
        restoreFocusAfterSave = defaults.object(forKey: Key.restoreFocusAfterSave) as? Bool ?? true
        hasCompletedSetup = defaults.object(forKey: Key.hasCompletedSetup) as? Bool ?? false
        let storedInputUID = defaults.string(forKey: Key.inputDeviceUID)
        inputDeviceUID = storedInputUID
        inputDeviceName = storedInputUID == nil ? nil : defaults.string(forKey: Key.inputDeviceName)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        shortcutRegistrationIssues = ShortcutSlot.allCases.compactMap { slot in
            let combo = combo(for: slot)
            if let conflict = shortcutConflict(for: combo, excluding: slot) {
                return .conflict(slot: slot, combo: combo, reason: conflict)
            }
            guard combo.isValid else { return .invalid(slot: slot, combo: combo) }
            return nil
        }

        for obsoleteKey in [
            "includeSource", "includeHeading", "clearAfterCopy",
        ] {
            defaults.removeObject(forKey: obsoleteKey)
        }
        persistProfiles()
        persistActiveProfileID()
    }

    func completeSetup() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true
        defaults.set(true, forKey: Key.hasCompletedSetup)
    }

    func combo(for slot: ShortcutSlot) -> KeyCombo { combos[slot]! }

    func shortcutConflict(for proposed: KeyCombo, excluding slot: ShortcutSlot) -> ShortcutConflict? {
        guard proposed.isValid else { return .invalid }

        let fixed: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]), "Close Window (⌘W)"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command]), "Undo (⌘Z)"),
        ]
        if let (_, name) = fixed.first(where: { $0.0 == proposed }) {
            return .reserved(name)
        }
        if let duplicate = ShortcutSlot.allCases.first(where: {
            $0 != slot && combo(for: $0) == proposed
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

    func updateShortcutRegistrationIssues(_ issues: [ShortcutRegistrationIssue]) {
        guard shortcutRegistrationIssues != issues else { return }
        shortcutRegistrationIssues = issues
    }

    func selectProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw ProfileMutationError.unknownProfile
        }
        guard activeProfileID != id else { return }
        activeProfileID = id
        persistActiveProfileID()
        onProfilesChanged?()
    }

    func updateProfile(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileMutationError.unknownProfile
        }
        var stored = profile
        stored.name = try validatedName(profile.name, excluding: profile.id)
        guard stored != profiles[index] else { return }
        profiles[index] = stored
        persistProfiles()
        onProfilesChanged?()
    }

    func addProfile(_ profile: Profile) throws {
        guard !profiles.contains(where: { $0.id == profile.id }) else {
            throw ProfileMutationError.duplicateName
        }
        var stored = profile
        stored.name = try validatedName(profile.name, excluding: nil)
        profiles.append(stored)
        persistProfiles()
        onProfilesChanged?()
    }

    @discardableResult
    func deleteProfile(id: UUID) throws -> UUID {
        guard profiles.count > 1 else { throw ProfileMutationError.lastProfile }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileMutationError.unknownProfile
        }
        profiles.remove(at: index)
        if activeProfileID == id {
            activeProfileID = profiles[min(index, profiles.count - 1)].id
            persistActiveProfileID()
        }
        persistProfiles()
        onProfilesChanged?()
        return activeProfileID
    }

    func profile(id: UUID) -> Profile? {
        profiles.first(where: { $0.id == id })
    }

    func validatedName(_ proposedName: String, excluding profileID: UUID?) throws -> String {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileMutationError.emptyName }
        let normalized = Self.normalizedProfileName(trimmed)
        guard !profiles.contains(where: {
            $0.id != profileID && Self.normalizedProfileName($0.name) == normalized
        }) else { throw ProfileMutationError.duplicateName }
        return trimmed
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
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    /// The stored list when every entry is usable, otherwise nil.
    private static func validProfiles(_ decoded: [Profile]?) -> [Profile]? {
        guard let decoded, !decoded.isEmpty else { return nil }
        var ids: Set<UUID> = []
        var names: Set<String> = []
        for profile in decoded {
            let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !trimmed.isEmpty,
                trimmed == profile.name,
                ids.insert(profile.id).inserted,
                names.insert(normalizedProfileName(profile.name)).inserted
            else { return nil }
        }
        return decoded
    }

    /// Built-ins keep their canonical order even in a list saved by an
    /// older build; the user's own templates follow in the order they were made.
    private static func builtInsFirst(_ profiles: [Profile]) -> [Profile] {
        let builtInIDs = Profile.builtIns.map(\.id)
        let builtIns = builtInIDs.compactMap { id in profiles.first { $0.id == id } }
        let custom = profiles.filter { !builtInIDs.contains($0.id) }
        return builtIns + custom
    }

    private static func normalizedProfileName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}
