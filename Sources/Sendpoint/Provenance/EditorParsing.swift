import Foundation

/// Parses the common focused-window format used by Code-OSS editor builds.
enum EditorProvenanceParser {
    static func fields(
        windowTitle: String?,
        document: String?,
        isDirectory: (URL) -> Bool
    ) -> ProvenanceFields {
        let documentURL = document.flatMap { LocalFileLocation.documentURL($0, localHosts: []) }
        let title = ParsedCodeEditorTitle(windowTitle)

        var url: URL?
        var workingDirectory: URL?

        if let documentURL {
            if isDirectory(documentURL) {
                workingDirectory = documentURL
            } else {
                url = documentURL
                workingDirectory = workspaceDirectory(containing: documentURL, title: title)
            }
        }

        if url == nil, let hint = title.documentHint {
            url = hint
            if workingDirectory == nil {
                workingDirectory = workspaceDirectory(containing: hint, title: title)
            }
        }
        if workingDirectory == nil {
            workingDirectory = title.directoryHint
        }
        return ProvenanceFields(url: url, workingDirectory: workingDirectory)
    }

    private static func workspaceDirectory(
        containing file: URL,
        title: ParsedCodeEditorTitle
    ) -> URL? {
        guard let name = title.workspaceName(matchingAncestorsOf: file) else { return nil }
        var directory = file.standardizedFileURL.deletingLastPathComponent()
        var match: URL?
        while directory.path != "/", !directory.path.isEmpty {
            if directory.lastPathComponent == name {
                match = URL(fileURLWithPath: directory.path).standardizedFileURL
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return match
    }
}

private struct ParsedCodeEditorTitle {
    var documentHint: URL?
    var directoryHint: URL?
    private var labels: [String] = []

    init(_ title: String?) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return }

        var remainder = Self.stripDirtyPrefix(title)
        remainder = Self.stripTrailingAppName(remainder)
        let segments = Self.stripTrailingProfile(Self.split(remainder))
        for segment in segments {
            guard let url = LocalFileLocation.documentURL(segment, localHosts: []) else {
                labels.append(segment)
                continue
            }
            if url.pathExtension.isEmpty {
                directoryHint = url
            } else {
                documentHint = url
            }
        }
    }

    func workspaceName(matchingAncestorsOf file: URL) -> String? {
        var ancestors = Set<String>()
        var directory = file.standardizedFileURL.deletingLastPathComponent()
        while directory.path != "/", !directory.path.isEmpty {
            ancestors.insert(directory.lastPathComponent)
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        for label in labels {
            let name = Self.normalizedWorkspaceName(label)
            if ancestors.contains(name) { return name }
        }
        return nil
    }

    private static let separators = [" — ", " – ", " - "]
    private static let dirtyPrefixes = ["● ", "• ", "* "]
    private static let trailingAppNames = [
        "Visual Studio Code - Insiders", "Visual Studio Code - Exploration",
        "Visual Studio Code", "VSCodium - Insiders", "VSCodium", "Code - OSS",
        "Cursor Nightly", "Cursor", "Windsurf Next", "Windsurf",
        "Antigravity IDE", "Antigravity", "T3 Code (Alpha)", "T3 Code",
        "Trae", "Zed Preview", "Zed", "Positron", "Code",
    ]

    private static func stripDirtyPrefix(_ title: String) -> String {
        for prefix in dirtyPrefixes where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    private static func stripTrailingAppName(_ title: String) -> String {
        for separator in separators {
            for appName in trailingAppNames {
                let suffix = separator + appName
                if title.lowercased().hasSuffix(suffix.lowercased()) {
                    return String(title.dropLast(suffix.count))
                }
            }
        }
        return title
    }

    private static func split(_ title: String) -> [String] {
        for separator in separators where title.contains(separator) {
            return title.components(separatedBy: separator).compactMap {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return [title]
    }

    private static func stripTrailingProfile(_ segments: [String]) -> [String] {
        guard let last = segments.last, last.hasSuffix(" (Profile)") else { return segments }
        return Array(segments.dropLast())
    }

    private static func normalizedWorkspaceName(_ segment: String) -> String {
        var name = segment
        if name.hasSuffix(" (Workspace)") {
            name = String(name.dropLast(" (Workspace)".count))
        }
        if name.hasSuffix("]"), let open = name.lastIndex(of: "["), open > name.startIndex {
            let before = name.index(before: open)
            if name[before] == " " { name = String(name[..<before]) }
        }
        return name
    }
}
