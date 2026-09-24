import Foundation
import XCTest
@testable import Sendpoint

final class ThemeTests: XCTestCase {
    func testLayoutTokenScale() {
        XCTAssertEqual([Radius.panel, Radius.card, Radius.chip], [14, 10, 6])
        XCTAssertEqual([Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl], [4, 8, 12, 16, 24, 48])
    }

    func testUIUsesThemeRatherThanLiteralStyling() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Sendpoint")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let patterns = [
            #"cornerRadius:\s*\d"#,
            #"spacing:\s*[1-9]\d*"#,
            #"\.padding\((?:\.[A-Za-z]+,\s*)?-?[1-9]\d*"#,
            #"\.padding\(\)"#,
            #"\.system\(size:|\.systemFont\(|NSFont\(name:"#,
            #"\b(?:Color|NSColor|CGColor)\((?:red:|white:|gray:)"#,
            #"\b(?:Color|NSColor)\.(?:primary|secondary|white|black|clear|labelColor)\b"#,
            #"\.foregroundStyle\(\.(?:primary|secondary|tertiary|quaternary|white|black)\b"#,
            #"\.(?:easeOut|easeInOut|linear|spring|snappy)\("#,
        ]
        for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "Theme.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                // The toggle's 2pt knob travel is intrinsic drawing geometry, not layout spacing.
                if file.lastPathComponent == "Controls.swift", line.contains(".padding(2) // Knob travel inset") { continue }
                for pattern in patterns {
                    XCTAssertNil(line.range(of: pattern, options: .regularExpression),
                                 "\(file.lastPathComponent):\(index + 1) should use Theme: \(line)")
                }
            }
        }
    }
}
