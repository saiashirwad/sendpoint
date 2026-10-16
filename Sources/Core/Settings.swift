import Foundation

// The settings window: what it shows lives in World, what it changes goes back
// into config.toml one line at a time, so the file stays the only source of truth.

public enum Pane: Int, CaseIterable, Sendable {
    case capture, card, stacks, system
}

public enum Setting: Equatable, Sendable {
    case key(Action, Shortcut?)
    case voice(VoiceMode)
    case name(Int, String)
    case lines(Int)
    case fontSize(Double)
    case opacity(Double)
    case width(Double)
}

/// A shortcut the window refused, shown under that action's row.
public struct Notice: Equatable, Sendable {
    public var action: Action
    public var text: String
}

public let actionTitles = [
    "Typed note", "Voice note", "Paste the stack", "Open the stack", "Stack 1", "Stack 2", "Stack 3", "Stack 4",
]

/// Needs ⌘, ⌥ or ⌃, and a key the config file can name.
public func isBindable(_ s: Shortcut) -> Bool {
    s.mods & (modCmd | modOpt | modCtrl) != 0 && keyCodes.contains(s.code)
}

func applySetting(_ w: inout World, _ setting: Setting) -> [Effect] {
    let wasRecording = w.recording != nil
    var c = w.config
    var written = setting
    switch setting {
    case .key(let action, let shortcut):
        if let shortcut {
            if !isBindable(shortcut) {
                w.notice = Notice(action: action, text: "Add ⌘, ⌥ or ⌃ to a letter, number or F-key.")
                return []
            }
            if let other = c.keys.firstIndex(of: shortcut), other != action.rawValue {
                w.notice = Notice(action: action, text: "\(shortcutLabel(shortcut)) is already \(actionTitles[other]).")
                return []
            }
        }
        c.keys[action.rawValue] = shortcut
        w.recording = nil
    case .voice(let mode):
        c.voice = mode
    case .name(let i, let name):
        guard c.names.indices.contains(i) else { return [] }
        let clean = trimmed(name.replacingOccurrences(of: "\"", with: ""))
        c.names[i] = clean.isEmpty ? "Stack \(i + 1)" : clean
        written = .name(i, c.names[i])
    case .lines(let n):
        c.lines = clampLines(n)
        written = .lines(c.lines)
    case .fontSize(let x):
        c.fontSize = clampFontSize(x)
        written = .fontSize(c.fontSize)
    case .opacity(let x):
        c.opacity = clampOpacity(x)
        written = .opacity(c.opacity)
    case .width(let x):
        c.width = clampWidth(x)
        written = .width(c.width)
    }
    w.notice = nil
    let rebind = wasRecording || c.keys != w.config.keys
    guard c != w.config else { return rebind ? [.bindKeys] : [] }
    w.config = c
    return [.writeConfig(written)] + (rebind ? [.bindKeys] : [])
}

// MARK: Writing config.toml

/// The file with `setting`'s line rewritten in place, comments and alignment kept.
/// A missing line goes at the end of its section; a missing section at the end of the file.
public func editConfig(_ text: String, _ setting: Setting) -> String {
    let (section, key, value) = configEntry(setting)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var current = ""
    var insertAt: Int?
    for i in lines.indices {
        let line = trimmed(stripComment(Substring(lines[i])))
        if line.hasPrefix("[") && line.hasSuffix("]") {
            current = trimmed(String(line.dropFirst().dropLast()))
            if current == section { insertAt = i + 1 }
            continue
        }
        guard current == section, !line.isEmpty else { continue }
        insertAt = i + 1
        if let eq = line.firstIndex(of: "="), trimmed(String(line[..<eq])) == key {
            lines[i] = replacingValue(lines[i], with: value)
            return lines.joined(separator: "\n")
        }
    }
    let entry = "\(key) = \(value)"
    if let insertAt {
        lines.insert(entry, at: insertAt)
    } else {
        let end = lines.last == "" ? lines.count - 1 : lines.count
        lines.insert(contentsOf: ["", "[\(section)]", entry], at: end)
    }
    return lines.joined(separator: "\n")
}

func configEntry(_ setting: Setting) -> (section: String, key: String, value: String) {
    switch setting {
    case .key(let a, let s): ("keys", actionNames[a.rawValue], quoted(s.map(shortcutText) ?? ""))
    case .voice(let mode): ("voice", "mode", quoted(mode.rawValue))
    case .name(let i, let name): ("stacks", "\(i + 1)", quoted(name))
    case .lines(let n): ("card", "lines", "\(n)")
    case .fontSize(let x): ("card", "font_size", number(x))
    case .opacity(let x): ("card", "opacity", number(x))
    case .width(let x): ("card", "width", number(x))
    }
}

/// The config file's spelling: "ctrl+opt+shift+cmd+k".
public func shortcutText(_ s: Shortcut) -> String {
    var parts: [String] = []
    if s.mods & modCtrl != 0 { parts.append("ctrl") }
    if s.mods & modOpt != 0 { parts.append("opt") }
    if s.mods & modShift != 0 { parts.append("shift") }
    if s.mods & modCmd != 0 { parts.append("cmd") }
    if let k = keyCodes.firstIndex(of: s.code) { parts.append(keyNames[k]) }
    return parts.joined(separator: "+")
}

private func replacingValue(_ line: String, with value: String) -> String {
    guard let eq = line.firstIndex(of: "=") else { return line }
    let rest = line[line.index(after: eq)...]
    let gap = rest.prefix { $0 == " " || $0 == "\t" }
    var out = String(line[...eq]) + (gap.isEmpty ? " " : String(gap)) + value
    if let hash = commentIndex(Substring(line)) {
        let column = line.distance(from: line.startIndex, to: hash)
        out += String(repeating: " ", count: max(column - out.count, 1)) + line[hash...]
    }
    return out
}

private func quoted(_ s: String) -> String { "\"\(s)\"" }

private func number(_ x: Double) -> String {
    x == x.rounded() ? "\(Int(x))" : "\(x)"
}
