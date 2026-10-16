import Foundation

// ~/.config/sendpoint/config.toml, parsed into flat data. A tiny TOML subset:
// [section] headers, `key = value` lines, # comments.

/// The case names are the config file's [keys] names.
public enum Action: Int, CaseIterable, Sendable {
    case note, speak, paste, open, stack1, stack2, stack3, stack4

    public var name: String { "\(self)" }
}

// Carbon modifier bits, so the App passes them straight to RegisterEventHotKey.
public let modCmd = 0x100, modShift = 0x200, modOpt = 0x800, modCtrl = 0x1000

public struct Shortcut: Equatable, Sendable {
    public var code: Int   // macOS virtual key code
    public var mods: Int

    public init(code: Int, mods: Int) {
        self.code = code
        self.mods = mods
    }
}

public enum VoiceMode: String, Equatable, Sendable {
    case hold, tap
}

public struct Config: Equatable, Sendable {
    /// Indexed by `Action.rawValue`; nil is unbound.
    public var keys: [Shortcut?] = [
        Shortcut(code: 5, mods: modCmd),             // note   ⌘G
        Shortcut(code: 14, mods: modCmd),            // speak  ⌘E
        Shortcut(code: 9, mods: modCtrl | modCmd),   // paste  ⌃⌘V
        Shortcut(code: 1, mods: modCtrl | modCmd),   // open   ⌃⌘S
        Shortcut(code: 4, mods: modOpt),             // ⌥H
        Shortcut(code: 38, mods: modOpt),            // ⌥J
        Shortcut(code: 40, mods: modOpt),            // ⌥K
        Shortcut(code: 37, mods: modOpt),            // ⌥L
    ]
    public var names = ["Reading notes", "Ideas", "Questions", "Scratch"]
    public var voice = VoiceMode.hold
    public var lines = 4
    public var fontSize = 14.0
    public var opacity = 0.86
    public var width = 460.0
    /// Human-readable complaints about the file; shown in the menu.
    public var problems: [String] = []

    public init() {}
}

public let defaultConfigText = """
# Sendpoint. Changes apply as soon as you save this file.
#
# A shortcut is modifiers joined by "+" (cmd, opt, ctrl, shift) and then a key:
# a-z, 0-9, f1-f12, space, return, tab, escape, delete, up, down, left, right,
# or one of , . / ; ' [ ] - = ` \\. Use "" to turn a shortcut off.

[keys]
note   = "cmd+g"        # type a note about the selection
speak  = "cmd+e"        # speak a note; see [voice]
paste  = "ctrl+cmd+v"   # paste the current stack as Markdown, then clear it
open   = "ctrl+cmd+s"   # open the current stack as a Markdown file
stack1 = "opt+h"        # switch stacks
stack2 = "opt+j"
stack3 = "opt+k"
stack4 = "opt+l"

[voice]
mode = "hold"   # hold: talk while the key is down, release to save
                # tap:  tap to start, tap again to save

[stacks]
1 = "Reading notes"
2 = "Ideas"
3 = "Questions"
4 = "Scratch"

[card]
lines     = 4      # lines of text the note card shows
font_size = 14
opacity   = 0.86   # 0.3 to 1
width     = 460

"""

public func parseConfig(_ text: String) -> Config {
    var c = Config()
    var section = ""
    var lineNumber = 0
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        lineNumber += 1
        let line = trimmed(stripComment(raw))
        if line.isEmpty { continue }
        if line.hasPrefix("[") && line.hasSuffix("]") {
            section = trimmed(String(line.dropFirst().dropLast()))
            if section != "keys" && section != "stacks" && section != "card" && section != "voice" {
                c.problems.append("line \(lineNumber): unknown section [\(section)]")
            }
            continue
        }
        guard let eq = line.firstIndex(of: "=") else {
            c.problems.append("line \(lineNumber): expected key = value")
            continue
        }
        let key = trimmed(String(line[..<eq]))
        var value = trimmed(String(line[line.index(after: eq)...]))
        if value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }

        switch section {
        case "keys":
            guard let a = Action.allCases.firstIndex(where: { $0.name == key }) else {
                c.problems.append("line \(lineNumber): unknown shortcut '\(key)'")
                continue
            }
            if value.isEmpty || value == "none" {
                c.keys[a] = nil
            } else if let s = parseShortcut(value) {
                c.keys[a] = s
            } else {
                c.problems.append("line \(lineNumber): can't read shortcut \"\(value)\" (needs cmd, opt or ctrl plus a key)")
            }
        case "stacks":
            guard let n = Int(key), n >= 1, n <= stackCount else {
                c.problems.append("line \(lineNumber): stacks are numbered 1 to \(stackCount)")
                continue
            }
            c.names[n - 1] = value.isEmpty ? "Stack \(n)" : value
        case "voice":
            guard key == "mode" else {
                c.problems.append("line \(lineNumber): unknown voice setting '\(key)'")
                continue
            }
            guard let mode = VoiceMode(rawValue: value) else {
                c.problems.append("line \(lineNumber): voice mode is \"hold\" or \"tap\"")
                continue
            }
            c.voice = mode
        case "card":
            guard let number = Double(value) else {
                c.problems.append("line \(lineNumber): \(key) needs a number")
                continue
            }
            switch key {
            case "lines": c.lines = Int(clamp(number, 1...12))
            case "font_size": c.fontSize = clamp(number, 9...32)
            case "opacity": c.opacity = clamp(number, 0.3...1)
            case "width": c.width = clamp(number, 280...1200)
            default: c.problems.append("line \(lineNumber): unknown card setting '\(key)'")
            }
        default:
            c.problems.append("line \(lineNumber): '\(key)' is outside a section")
        }
    }

    // Two actions on one chord: the later one loses.
    for a in 0..<c.keys.count {
        guard let s = c.keys[a] else { continue }
        for b in 0..<a where c.keys[b] == s {
            let (later, earlier) = (Action.allCases[a].name, Action.allCases[b].name)
            c.problems.append("\(later) and \(earlier) both use \(shortcutLabel(s)); \(later) is off")
            c.keys[a] = nil
            break
        }
    }
    return c
}

public func parseShortcut(_ text: String) -> Shortcut? {
    let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { trimmed(String($0)) }
    // "cmd++" would split into an empty last part; "+" isn't a supported key anyway.
    guard let last = parts.last, let k = keyNames.firstIndex(of: last) else { return nil }
    var mods = 0
    for part in parts.dropLast() {
        switch part {
        case "cmd", "command", "⌘": mods |= modCmd
        case "opt", "option", "alt", "⌥": mods |= modOpt
        case "ctrl", "control", "⌃": mods |= modCtrl
        case "shift", "⇧": mods |= modShift
        default: return nil
        }
    }
    guard mods & (modCmd | modOpt | modCtrl) != 0 else { return nil }
    return Shortcut(code: keyCodes[k], mods: mods)
}

public func shortcutLabel(_ s: Shortcut) -> String {
    var out = ""
    if s.mods & modCtrl != 0 { out += "⌃" }
    if s.mods & modOpt != 0 { out += "⌥" }
    if s.mods & modShift != 0 { out += "⇧" }
    if s.mods & modCmd != 0 { out += "⌘" }
    guard let k = keyCodes.firstIndex(of: s.code) else { return out + "?" }
    return out + keyLabels[k]
}

func clamp(_ x: Double, _ range: ClosedRange<Double>) -> Double {
    min(max(x, range.lowerBound), range.upperBound)
}

/// The line up to its first unquoted #.
func stripComment(_ line: Substring) -> String {
    var quoted = false
    for i in line.indices {
        if line[i] == "\"" { quoted.toggle() }
        if line[i] == "#" && !quoted { return String(line[..<i]) }
    }
    return String(line)
}

// ANSI virtual key codes (Carbon kVK_*), as parallel arrays.
public let keyNames = [
    "a", "s", "d", "f", "h", "g", "z", "x", "c", "v", "b", "q", "w", "e", "r", "y", "t",
    "1", "2", "3", "4", "6", "5", "=", "9", "7", "-", "8", "0", "]", "o", "u", "[", "i", "p",
    "return", "l", "j", "'", "k", ";", "\\", ",", "/", "n", "m", ".", "tab", "space", "`", "delete", "escape",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    "left", "right", "down", "up",
]
public let keyCodes = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
    18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 53,
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
    123, 124, 125, 126,
]
let keyLabels = [
    "A", "S", "D", "F", "H", "G", "Z", "X", "C", "V", "B", "Q", "W", "E", "R", "Y", "T",
    "1", "2", "3", "4", "6", "5", "=", "9", "7", "-", "8", "0", "]", "O", "U", "[", "I", "P",
    "↩", "L", "J", "'", "K", ";", "\\", ",", "/", "N", "M", ".", "⇥", "Space", "`", "⌫", "⎋",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "←", "→", "↓", "↑",
]
