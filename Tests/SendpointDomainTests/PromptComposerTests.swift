import Foundation
import XCTest

@testable import SendpointDomain

final class PromptComposerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_735_831_440)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testTextNormalizationTrimsAndCaseFoldsStackIdentity() {
        XCTAssertEqual("  Reading Notes \n".nonblank, "Reading Notes")
        XCTAssertEqual("  Reading Notes \n".normalizedStackName, "reading notes")
        XCTAssertEqual("READING NOTES".normalizedStackName, "reading notes")
        XCTAssertEqual("Résumé".normalizedStackName, "resume")
        XCTAssertEqual("ＲＥＡＤＩＮＧ".normalizedStackName, "reading")
        XCTAssertNil(" \n\t".nonblank)
        XCTAssertNil(" \n\t".normalizedStackName)
    }

    func testComposerIncludesPreambleHeadingEntriesAndTimestamp() {
        let output = compose(template: .coherent)

        XCTAssertTrue(output.contains("# Reading notes — January 2, 2025"))
        XCTAssertEqual(output.components(separatedBy: Template.coherent.preamble).count - 1, 1)
        XCTAssertFalse(output.contains("## "))
        XCTAssertTrue(output.contains("_\(expectedTime)_"))
    }

    func testComposerNumbersEntriesOnlyWhenTheTemplateEnablesIt() {
        let numbered = compose(template: .pointByPoint)
        XCTAssertTrue(numbered.contains("## 1"))
        XCTAssertTrue(numbered.contains("## 2"))

        var unnumbered = Template.pointByPoint
        unnumbered.includeNoteNumbers = false
        XCTAssertFalse(compose(template: unnumbered).contains("## "))
    }

    func testComposerOmitsWhitespaceOnlyPreambleWithoutTrimmingNonblankContent() {
        var template = Template.plain
        template.preamble = "  \n\t"
        XCTAssertEqual(compose(template: template), compose(template: .plain))

        template.preamble = "  Keep this spacing  "
        XCTAssertTrue(compose(template: template).hasPrefix("  Keep this spacing  \n\n> First line"))
    }

    func testPlainComposerFormatsSelectionAndStandaloneEntriesExactly() {
        let output = compose(template: .plain)

        XCTAssertEqual(
            output,
            """
            > First line
            > Second line
            >
            > Fourth line

            Response to selection

            A standalone thought
            """
        )
        XCTAssertFalse(output.contains("Reading notes"))
    }

    private var expectedTime: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func compose(template: Template) -> String {
        compose(stack: makeStack(), template: template)
    }

    private func compose(stack: Stack, template: Template) -> String {
        PromptComposer.markdown(
            stack: stack,
            template: template,
            calendar: Calendar(identifier: .gregorian),
            locale: locale,
            timeZone: timeZone
        )
    }

    private func makeStack() -> Stack {
        Stack(
            name: "Reading",
            notes: [
                Note(
                    subject: .selection(quote: "First line\nSecond line\n\nFourth line"),
                    body: "Response to selection",
                    createdAt: date
                ),
                Note(
                    subject: .standalone,
                    body: "A standalone thought",
                    createdAt: date
                ),
            ],
            createdAt: date
        )
    }
}
