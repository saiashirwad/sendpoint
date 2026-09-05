import Foundation

enum LocalFileLocation {
    static var localHosts: Set<String> {
        Set(Host.current().names + [ProcessInfo.processInfo.hostName, "localhost"])
    }

    static func isLocalHost(_ host: String, localHosts: Set<String>) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return localHosts.contains { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized }
    }

    /// These values are raw filesystem paths, not URL strings. Preserve spaces,
    /// newlines, percent signs, '?' and '#' literally.
    static func absolutePath(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\0") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func documentURL(_ value: String, localHosts: Set<String>) -> URL? {
        if value.hasPrefix("/") { return absolutePath(value) }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "file",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil
        else { return nil }
        if let host = components.host, !host.isEmpty,
           !isLocalHost(host, localHosts: localHosts) { return nil }
        return absolutePath(components.path)
    }
}
