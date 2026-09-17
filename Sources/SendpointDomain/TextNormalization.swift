import Foundation

private let normalizationLocale = Locale(identifier: "en_US_POSIX")

public extension String {
    var nonblank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedName: String? {
        guard let trimmed = nonblank else { return nil }
        let normalized = trimmed
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: normalizationLocale
            )
            .lowercased(with: normalizationLocale)
        return normalized.isEmpty ? nil : normalized
    }
}

public extension Sequence {
    func matching(_ query: String, text: (Element) -> String) -> [Element] {
        guard let needle = query.normalizedName else { return Array(self) }
        return filter { text($0).normalizedName?.contains(needle) == true }
    }
}
