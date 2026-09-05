import AppKit
import ApplicationServices
import Foundation

@globalActor
actor ProvenanceSystemActor {
    static let shared = ProvenanceSystemActor()
}

@ProvenanceSystemActor
enum ProvenanceSystemBoundary {
    private static let accessibilityTimeout: Float = 1

    static func matchesCapturedApplication(_ captured: CapturedApplication) throws -> Bool {
        try Task.checkCancellation()
        guard let application = NSRunningApplication(
            processIdentifier: captured.processIdentifier
        ) else { return false }
        try Task.checkCancellation()
        guard !application.isTerminated else { return false }
        if let bundleID = captured.identity.bundleID {
            return application.bundleIdentifier == bundleID
        }
        return application.bundleIdentifier == nil
            && application.localizedName == captured.identity.name
    }

    static func focusedWindowFields(processIdentifier: pid_t) throws -> ProvenanceFields {
        guard let window = try focusedWindow(processIdentifier: processIdentifier) else {
            return ProvenanceFields()
        }
        return ProvenanceFields(windowTitle: try stringValue(window, kAXTitleAttribute))
    }

    static func documentDirectoryFields(processIdentifier: pid_t) throws -> ProvenanceFields {
        guard let window = try focusedWindow(processIdentifier: processIdentifier) else {
            return ProvenanceFields()
        }
        let title = try stringValue(window, kAXTitleAttribute)
        let document = try stringValue(window, kAXDocumentAttribute)
        return ProvenanceFields(
            windowTitle: title,
            workingDirectory: document.flatMap {
                LocalFileLocation.documentURL($0, localHosts: LocalFileLocation.localHosts)
            }
        )
    }

    static func codeEditorFields(processIdentifier: pid_t) throws -> ProvenanceFields {
        guard let window = try focusedWindow(processIdentifier: processIdentifier) else {
            return ProvenanceFields()
        }
        let title = try stringValue(window, kAXTitleAttribute)
        let document = try stringValue(window, kAXDocumentAttribute)
        try Task.checkCancellation()
        let parsed = EditorProvenanceParser.fields(
            windowTitle: title,
            document: document,
            isDirectory: isDirectoryOnDisk
        )
        try Task.checkCancellation()
        return ProvenanceFields(
            windowTitle: title,
            url: parsed.url,
            workingDirectory: parsed.workingDirectory
        )
    }

    private static func isDirectoryOnDisk(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// osascript's source form preserves list boundaries and embedded newlines.
    /// Run out of process because Automation dialogs can outlive AppleScript timeouts.
    static func appleScriptValues(_ source: String) async throws -> [String]? {
        let output = try await ProvenanceCommand.output(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-s", "s", "-e", source]
        )
        try Task.checkCancellation()
        return AppleScriptListParser.values(from: String(decoding: output, as: UTF8.self))
    }

    private static func focusedWindow(processIdentifier: pid_t) throws -> AXUIElement? {
        guard processIdentifier > 0 else { return nil }
        try Task.checkCancellation()
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, accessibilityTimeout)
        try Task.checkCancellation()
        guard let value = try copiedValue(application, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringValue(
        _ element: AXUIElement,
        _ attribute: String
    ) throws -> String? {
        try copiedValue(element, attribute).flatMap { value in
            guard let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : string
        }
    }

    private static func copiedValue(
        _ element: AXUIElement,
        _ attribute: String
    ) throws -> CFTypeRef? {
        var value: CFTypeRef?
        try Task.checkCancellation()
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        try Task.checkCancellation()
        guard result == .success else { return nil }
        return value
    }
}
