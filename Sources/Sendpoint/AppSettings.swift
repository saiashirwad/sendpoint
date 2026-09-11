import Foundation
import Observation
import ServiceManagement

enum StackExportMode: Equatable, Sendable {
    case paste
    case copy

    init(pasteDirectly: Bool) { self = pasteDirectly ? .paste : .copy }

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

    var exportMomentCaption: String {
        switch self {
        case .paste: "When you paste"
        case .copy: "When you copy"
        }
    }
}

@Observable
final class AppSettings {
    private enum Key {
        static let pasteDirectly = "pasteDirectly"
        static let restoreFocusAfterSave = "restoreFocusAfterSave"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    private let defaults: UserDefaults
    private let registerLoginItem: @MainActor () throws -> Void
    private let unregisterLoginItem: @MainActor () throws -> Void

    private(set) var pasteDirectly: Bool
    private(set) var restoreFocusAfterSave: Bool
    private(set) var hasCompletedSetup: Bool
    private(set) var launchAtLogin: Bool

    var stackExportMode: StackExportMode { StackExportMode(pasteDirectly: pasteDirectly) }

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
        pasteDirectly = defaults.object(forKey: Key.pasteDirectly) as? Bool ?? true
        restoreFocusAfterSave = defaults.object(forKey: Key.restoreFocusAfterSave) as? Bool ?? true
        hasCompletedSetup = defaults.object(forKey: Key.hasCompletedSetup) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setPasteDirectly(_ enabled: Bool) {
        guard pasteDirectly != enabled else { return }
        pasteDirectly = enabled
        defaults.set(enabled, forKey: Key.pasteDirectly)
    }

    func setRestoreFocusAfterSave(_ enabled: Bool) {
        guard restoreFocusAfterSave != enabled else { return }
        restoreFocusAfterSave = enabled
        defaults.set(enabled, forKey: Key.restoreFocusAfterSave)
    }

    func completeSetup() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true
        defaults.set(true, forKey: Key.hasCompletedSetup)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != launchAtLogin else { return }
        do {
            if enabled { try registerLoginItem() }
            else { try unregisterLoginItem() }
            launchAtLogin = enabled
        } catch {
            NSLog("Sendpoint: login item change failed: \(error)")
            launchAtLogin = !enabled
        }
    }
}
