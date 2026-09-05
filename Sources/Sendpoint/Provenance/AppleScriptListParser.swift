import Foundation

/// Parses only the list-of-strings subset emitted by `osascript -s s`.
/// No evaluation, delimiter splitting, or coercion of missing values into paths.
enum AppleScriptListParser {
    static func values(from source: String) -> [String]? {
        var input = source[...]
        func skipWhitespace() {
            input = input.drop(while: { $0.isWhitespace })
        }
        func consume(_ character: Character) -> Bool {
            guard input.first == character else { return false }
            input.removeFirst()
            return true
        }
        skipWhitespace()
        guard consume("{") else { return nil }
        skipWhitespace()
        var values: [String] = []
        if consume("}") {
            skipWhitespace()
            return input.isEmpty ? [] : nil
        }
        while !input.isEmpty {
            guard consume("\"") else { return nil }
            var value = ""
            var closed = false
            while let character = input.first {
                input.removeFirst()
                if character == "\"" {
                    closed = true
                    break
                }
                if character == "\\" {
                    guard let escaped = input.first else { return nil }
                    input.removeFirst()
                    switch escaped {
                    case "\\", "\"": value.append(escaped)
                    case "n": value.append("\n")
                    case "r": value.append("\r")
                    case "t": value.append("\t")
                    default: return nil
                    }
                } else {
                    value.append(character)
                }
            }
            guard closed else { return nil }
            values.append(value)
            skipWhitespace()
            if consume("}") {
                skipWhitespace()
                return input.isEmpty ? values : nil
            }
            guard consume(",") else { return nil }
            skipWhitespace()
        }
        return nil
    }
}
