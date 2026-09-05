import Foundation

public extension String {
    var nonblank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedSessionName: String? {
        guard let trimmed = nonblank else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        let normalized = trimmed
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
        return normalized.isEmpty ? nil : normalized
    }
}

public extension Sequence {
    /// The elements whose `text` contains `query`, compared case-, diacritic-,
    /// and width-insensitively. A blank query keeps everything.
    func matching(_ query: String, text: (Element) -> String) -> [Element] {
        guard let needle = query.normalizedSessionName else { return Array(self) }
        return filter { text($0).normalizedSessionName?.contains(needle) == true }
    }
}
