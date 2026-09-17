import Foundation
import Observation
import ServiceManagement

enum StackExportMode: Equatable, Sendable {
    case paste
    case copy

    init(pasteDirectly: Bool) { self = pasteDirectly ? .paste : .copy }

    var shortcutTitle: String {
        switch self {
        case .paste: "Paste the stack"
        case .copy: "Copy the stack"
        }
    }

    var shortcutHint: String {
        switch self {
        case .paste: "At the cursor, as Markdown"
        case .copy: "To the clipboard, as Markdown"
        }
    }

    var clearAfterExportTitle: String {
        switch self {
        case .paste: "Clear the stack after pasting"
        case .copy: "Clear the stack after copying"
        }
    }
}

enum AppSettingsEvent: Equatable {
    case launchAtLogin(Bool)
    case exportMode(StackExportMode)
    case restoreFocusAfterSave(Bool)
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

    func send(_ event: AppSettingsEvent) {
        switch event {
        case .launchAtLogin(let enabled): setLaunchAtLogin(enabled)
        case .exportMode(let mode): setPasteDirectly(mode == .paste)
        case .restoreFocusAfterSave(let enabled): setRestoreFocusAfterSave(enabled)
        }
    }
}
