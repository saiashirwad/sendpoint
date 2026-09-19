import Foundation
import XCTest

@testable import SendpointDomain

final class PromptComposerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_735_831_440)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testTextNormalizationTrimsAndCaseFoldsStackIdentity() {
        XCTAssertEqual("  Reading Notes \n".nonblank, "Reading Notes")
        XCTAssertEqual("  Reading Notes \n".normalizedName, "reading notes")
        XCTAssertEqual("READING NOTES".normalizedName, "reading notes")
        XCTAssertEqual("Résumé".normalizedName, "resume")
        XCTAssertEqual("ＲＥＡＤＩＮＧ".normalizedName, "reading")
        XCTAssertNil(" \n\t".nonblank)
        XCTAssertNil(" \n\t".normalizedName)
    }

    func testComposerIncludesPreambleHeadingEntriesAndTimestamp() {
        let output = compose(template: .coherent)

        XCTAssertTrue(output.contains("# Reading notes — January 2, 2025"))
        XCTAssertEqual(output.components(separatedBy: Template.coherent.preamble).count - 1, 1)
        XCTAssertFalse(output.contains("## "))
        XCTAssertTrue(output.contains("_\(expectedTime)_"))
    }

    func testTimestampsCarryTheDateOnceAStackSpansDays() {
        let nextDay = date.addingTimeInterval(86_400)
        let stack = Stack(notes: [
            Note(subject: .standalone, body: "Thursday", createdAt: date),
            Note(subject: .standalone, body: "Friday", createdAt: nextDay),
        ])
        let output = compose(stack: stack, template: .coherent)

        XCTAssertTrue(output.contains("Jan 2, 2025"), output)
        XCTAssertTrue(output.contains("Jan 3, 2025"), output)
        XCTAssertFalse(compose(template: .coherent).contains("Jan 2, 2025"), "one day needs only the time")
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
            ]
        )
    }
}
