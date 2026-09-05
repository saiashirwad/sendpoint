import AppKit
import Foundation

extension ProvenanceProvider {
    static let kitty = Self(bundleIDs: ["net.kovidgoyal.kitty"]) { application in
        try await KittyProvenanceLookup.live.fields(for: application)
    }
}

struct KittyProvenanceLookup: Sendable {
    var socketPaths: @Sendable (CapturedApplication) async throws -> [String]
    var readWindows: @Sendable (CapturedApplication, String) async throws -> Data

    func fields(for application: CapturedApplication) async throws -> ProvenanceFields {
        try Task.checkCancellation()
        let paths = try await socketPaths(application)
        try Task.checkCancellation()
        // Usually there is one listening socket. Do not spend unbounded time
        // trying unrelated UNIX sockets owned by this process.
        for path in paths.prefix(4) {
            do {
                let firstData = try await readWindows(application, path)
                try Task.checkCancellation()
                guard let first = try KittyWindowParser.selection(from: firstData) else { continue }
                let secondData = try await readWindows(application, path)
                try Task.checkCancellation()
                guard let second = try KittyWindowParser.selection(from: secondData),
                      first.windowID == second.windowID, first.tabID == second.tabID,
                      first.paneID == second.paneID, first.pid == second.pid,
                      first.cwd == second.cwd else { return ProvenanceFields() }
                return ProvenanceFields(
                    windowTitle: second.title.isEmpty ? nil : second.title,
                    workingDirectory: LocalFileLocation.absolutePath(first.cwd)
                )
            } catch {
                try Task.checkCancellation()
                // A missing socket, disabled remote control, or password denial
                // leaves the generic window provenance intact.
            }
        }
        return ProvenanceFields()
    }

    static let live = Self(
        socketPaths: { application in
            let data = try await ProvenanceCommand.output(
                executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-n", "-P", "-a", "-p", String(application.processIdentifier), "-U", "-F0n"]
            )
            return KittySocketParser.paths(from: data)
        },
        readWindows: { application, socket in
            guard try await ProvenanceSystemBoundary.matchesCapturedApplication(application),
                  let executable = await ProvenanceSystemBoundary.kittyExecutable(application)
            else { return Data() }
            return try await ProvenanceCommand.output(
                executable: executable,
                arguments: ["@", "--to", "unix:\(socket)", "ls", "--match", "state:focused"]
            )
        }
    )
}

extension ProvenanceSystemBoundary {
    static func kittyExecutable(_ application: CapturedApplication) -> URL? {
        NSRunningApplication(processIdentifier: application.processIdentifier)?.bundleURL?
            .appendingPathComponent("Contents/MacOS/kitten")
    }
}

enum KittySocketParser {
    /// lsof's NUL field mode preserves spaces and newlines in socket paths.
    static func paths(from data: Data) -> [String] {
        var seen: Set<String> = []
        return data.split(separator: 0).compactMap { field in
            let bytes = field.drop(while: { $0 == 10 })
            guard bytes.first == Character("n").asciiValue else { return nil }
            let path = String(decoding: bytes.dropFirst(), as: UTF8.self)
            guard path.hasPrefix("/"), !path.contains(" -> "), seen.insert(path).inserted else { return nil }
            return path
        }
    }
}

enum KittyWindowParser {
    struct Selection: Equatable, Sendable {
        let windowID: Int
        let tabID: Int
        let paneID: Int
        let pid: Int
        let title: String
        let cwd: String
    }

    private struct Window: Decodable {
        let id: Int
        let tabs: [Tab]
    }
    private struct Tab: Decodable {
        let id: Int
        let windows: [Pane]
    }
    private struct Pane: Decodable {
        let id: Int
        let pid: Int
        let title: String
        let cwd: String
    }

    /// The request uses `ls --match state:focused`, so exactly one pane must
    /// remain. Unlike is_focused, that match also works after Sendpoint takes focus.
    static func selection(from data: Data) throws -> Selection? {
        let windows = try JSONDecoder().decode([Window].self, from: data)
        let selections = windows.flatMap { window in
            window.tabs.flatMap { tab in
                tab.windows.map { pane in
                    Selection(windowID: window.id, tabID: tab.id, paneID: pane.id,
                              pid: pane.pid, title: pane.title, cwd: pane.cwd)
                }
            }
        }
        guard selections.count == 1, let selection = selections.first,
              selection.pid > 0 else { return nil }
        return selection
    }
}
