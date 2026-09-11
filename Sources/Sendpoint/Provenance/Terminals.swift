import Foundation

nonisolated extension ProvenanceProvider {
    static let ghostty = Self(bundleIDs: ["com.mitchellh.ghostty"]) { application in
        try await ProvenanceSystemBoundary.documentDirectoryFields(
            processIdentifier: application.processIdentifier
        )
    }

    static let terminal = Self(bundleIDs: ["com.apple.Terminal"]) { application in
        try await TerminalSessionLookup.live.fields(for: application)
    }
}

/// The selected tab. Re-read its identity after the process lookup so a tab
/// switch or closed session cannot mix results.
nonisolated struct TerminalSessionSnapshot: Equatable, Sendable {
    let windowID: String
    let stackID: String
    let title: String
    let tty: String

    init?(values: [String]) {
        guard values.count == 4, !values[0].isEmpty, !values[1].isEmpty else { return nil }
        windowID = values[0]
        stackID = values[1]
        title = values[2]
        tty = values[3]
    }
}

nonisolated struct TerminalSessionLookup: Sendable {
    var readStack: @Sendable (CapturedApplication) async throws -> TerminalSessionSnapshot?
    var directoryForTTY: @Sendable (String, CapturedApplication) async throws -> URL?

    func fields(for application: CapturedApplication) async throws -> ProvenanceFields {
        try Task.checkCancellation()
        guard let session = try await readStack(application) else { return ProvenanceFields() }
        try Task.checkCancellation()
        let directory = try await directoryForTTY(session.tty, application)
        try Task.checkCancellation()
        guard let current = try await readStack(application),
              current.windowID == session.windowID,
              current.stackID == session.stackID,
              current.tty == session.tty else { return ProvenanceFields() }
        try Task.checkCancellation()
        return ProvenanceFields(
            windowTitle: current.title.isEmpty ? nil : current.title,
            workingDirectory: directory
        )
    }

    static let live = Self(
        readStack: { application in
            guard try await ProvenanceSystemBoundary.matchesCapturedApplication(application),
                  let values = try await ProvenanceSystemBoundary.appleScriptValues(TerminalSessionScript.terminal)
            else { return nil }
            return TerminalSessionSnapshot(values: values)
        },
        directoryForTTY: { tty, application in
            try await ProvenanceSystemBoundary.directoryForTTY(
                tty, applicationPID: application.processIdentifier
            )
        }
    )
}

nonisolated enum TerminalSessionScript {
    static let terminal = """
    with timeout of 2 seconds
        tell application id "com.apple.Terminal"
            if not (exists front window) then return {}
            set selectedWindow to front window
            set selectedTTY to tty of selected tab of selectedWindow
            return {id of selectedWindow as text, selectedTTY, name of selectedWindow as text, selectedTTY}
        end tell
    end timeout
    """
}
