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

    func testComposerIncludesPreambleHeadingEntriesAndFullMetadata() {
        let output = compose(template: .coherent)

        XCTAssertTrue(output.contains("# Reading notes — January 2, 2025"))
        XCTAssertEqual(output.components(separatedBy: Template.coherent.preamble).count - 1, 1)
        XCTAssertFalse(output.contains("## "))
        XCTAssertEqual(
            metadata(in: output),
            ["Helium", "Page title", "https://example.com/article", "/tmp/project", expectedTime]
        )
    }

    func testComposerNumbersEntriesOnlyWhenTheTemplateEnablesIt() {
        let numbered = compose(template: .pointByPoint)
        XCTAssertTrue(numbered.contains("## 1"))
        XCTAssertTrue(numbered.contains("## 2"))

        var unnumbered = Template.pointByPoint
        unnumbered.includeNoteNumbers = false
        XCTAssertFalse(compose(template: unnumbered).contains("## "))
    }

    func testComposerKeepsAllMetadataFlagsIndependent() {
        var applicationOnly = Template.plain
        applicationOnly.includeApplication = true
        XCTAssertEqual(metadata(in: compose(template: applicationOnly)), ["Helium"])

        var windowOnly = Template.plain
        windowOnly.includeWindow = true
        XCTAssertEqual(metadata(in: compose(template: windowOnly)), ["Page title"])

        var linkOnly = Template.plain
        linkOnly.includeLink = true
        XCTAssertEqual(
            metadata(in: compose(template: linkOnly)),
            ["https://example.com/article", "/tmp/project"]
        )

        var timestampOnly = Template.plain
        timestampOnly.includeTimestamps = true
        XCTAssertEqual(metadata(in: compose(template: timestampOnly)), [expectedTime])
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
        XCTAssertFalse(output.contains("Helium"))
    }

    func testComposerDisplaysWebFileAndDirectoryLinksWithoutCouplingThem() {
        var template = Template.plain
        template.includeLink = true

        let webOnly = makeStack(
            provenance: Provenance(
                application: ApplicationIdentity(name: "Browser"),
                url: URL(string: "https://example.com/article")
            )
        )
        XCTAssertEqual(metadata(in: compose(stack: webOnly, template: template)), ["https://example.com/article"])

        let file = URL(fileURLWithPath: NSHomeDirectory() + "/code/Main.swift")
        let workspace = URL(fileURLWithPath: NSHomeDirectory() + "/code")
        let fileAndDirectory = makeStack(
            provenance: Provenance(
                application: ApplicationIdentity(name: "Editor"),
                url: file,
                workingDirectory: workspace
            )
        )
        XCTAssertEqual(
            metadata(in: compose(stack: fileAndDirectory, template: template)),
            ["~/code/Main.swift", "~/code"]
        )
    }

    func testBlankProvenanceFactsDoNotCreateEmptyMetadataBlock() {
        let note = Note(
            subject: .standalone,
            body: "Note",
            provenance: Provenance(
                application: ApplicationIdentity(name: "  "),
                windowTitle: "\n"
            ),
            createdAt: date
        )
        let stack = Stack(name: "Empty facts", notes: [note], createdAt: date)
        var template = Template.plain
        template.includeApplication = true
        template.includeWindow = true

        XCTAssertEqual(compose(stack: stack, template: template), "Note")
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

    private func metadata(in markdown: String) -> [String] {
        guard
            let line = markdown
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .first(where: { $0.hasPrefix("_") && $0.hasSuffix("_") })
        else { return [] }
        return String(line.dropFirst().dropLast()).components(separatedBy: " · ")
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

    private func makeStack(
        provenance: Provenance = Provenance(
            application: ApplicationIdentity(name: "Helium", bundleID: "com.example.helium"),
            windowTitle: "Page title",
            url: URL(string: "https://example.com/article"),
            workingDirectory: URL(fileURLWithPath: "/tmp/project")
        )
    ) -> Stack {
        Stack(
            name: "Reading",
            notes: [
                Note(
                    subject: .selection(quote: "First line\nSecond line\n\nFourth line"),
                    body: "Response to selection",
                    provenance: provenance,
                    createdAt: date
                ),
                Note(
                    subject: .standalone,
                    body: "A standalone thought",
                    provenance: provenance,
                    createdAt: date
                ),
            ],
            createdAt: date
        )
    }
}
