import Foundation
import XCTest

@testable import SendpointDomain

final class PromptComposerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_735_831_440)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testTextNormalizationTrimsAndCaseFoldsSessionIdentity() {
        XCTAssertEqual("  Reading Notes \n".nonblank, "Reading Notes")
        XCTAssertEqual("  Reading Notes \n".normalizedSessionName, "reading notes")
        XCTAssertEqual("READING NOTES".normalizedSessionName, "reading notes")
        XCTAssertEqual("Résumé".normalizedSessionName, "resume")
        XCTAssertEqual("ＲＥＡＤＩＮＧ".normalizedSessionName, "reading")
        XCTAssertNil(" \n\t".nonblank)
        XCTAssertNil(" \n\t".normalizedSessionName)
    }

    func testComposerIncludesPreambleHeadingEntriesAndFullMetadata() {
        let output = compose(profile: .coherent)

        XCTAssertTrue(output.contains("# Reading notes — January 2, 2025"))
        XCTAssertEqual(output.components(separatedBy: Profile.coherent.preamble).count - 1, 1)
        XCTAssertFalse(output.contains("## "))
        XCTAssertEqual(
            metadata(in: output),
            ["Helium", "Page title", "https://example.com/article", "/tmp/project", expectedTime]
        )
    }

    func testComposerNumbersEntriesOnlyWhenTheProfileEnablesIt() {
        let numbered = compose(profile: .pointByPoint)
        XCTAssertTrue(numbered.contains("## 1"))
        XCTAssertTrue(numbered.contains("## 2"))

        var unnumbered = Profile.pointByPoint
        unnumbered.includeEntryNumbers = false
        XCTAssertFalse(compose(profile: unnumbered).contains("## "))
    }

    func testComposerKeepsAllMetadataFlagsIndependent() {
        var applicationOnly = Profile.plain
        applicationOnly.includeApplication = true
        XCTAssertEqual(metadata(in: compose(profile: applicationOnly)), ["Helium"])

        var windowOnly = Profile.plain
        windowOnly.includeWindow = true
        XCTAssertEqual(metadata(in: compose(profile: windowOnly)), ["Page title"])

        var linkOnly = Profile.plain
        linkOnly.includeLink = true
        XCTAssertEqual(
            metadata(in: compose(profile: linkOnly)),
            ["https://example.com/article", "/tmp/project"]
        )

        var timestampOnly = Profile.plain
        timestampOnly.includeTimestamps = true
        XCTAssertEqual(metadata(in: compose(profile: timestampOnly)), [expectedTime])
    }

    func testComposerOmitsWhitespaceOnlyPreambleWithoutTrimmingNonblankContent() {
        var profile = Profile.plain
        profile.preamble = "  \n\t"
        XCTAssertEqual(compose(profile: profile), compose(profile: .plain))

        profile.preamble = "  Keep this spacing  "
        XCTAssertTrue(compose(profile: profile).hasPrefix("  Keep this spacing  \n\n> First line"))
    }

    func testPlainComposerFormatsSelectionAndStandaloneEntriesExactly() {
        let output = compose(profile: .plain)

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
        var profile = Profile.plain
        profile.includeLink = true

        let webOnly = makeSession(
            provenance: Provenance(
                application: ApplicationIdentity(name: "Browser"),
                url: URL(string: "https://example.com/article")
            )
        )
        XCTAssertEqual(metadata(in: compose(session: webOnly, profile: profile)), ["https://example.com/article"])

        let file = URL(fileURLWithPath: NSHomeDirectory() + "/code/Main.swift")
        let workspace = URL(fileURLWithPath: NSHomeDirectory() + "/code")
        let fileAndDirectory = makeSession(
            provenance: Provenance(
                application: ApplicationIdentity(name: "Editor"),
                url: file,
                workingDirectory: workspace
            )
        )
        XCTAssertEqual(
            metadata(in: compose(session: fileAndDirectory, profile: profile)),
            ["~/code/Main.swift", "~/code"]
        )
    }

    func testBlankProvenanceFactsDoNotCreateEmptyMetadataBlock() {
        let annotation = Annotation(
            subject: .standalone,
            note: "Note",
            provenance: Provenance(
                application: ApplicationIdentity(name: "  "),
                windowTitle: "\n"
            ),
            createdAt: date
        )
        let session = Session(name: "Empty facts", entries: [annotation], createdAt: date)
        var profile = Profile.plain
        profile.includeApplication = true
        profile.includeWindow = true

        XCTAssertEqual(compose(session: session, profile: profile), "Note")
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

    private func compose(profile: Profile) -> String {
        compose(session: makeSession(), profile: profile)
    }

    private func compose(session: Session, profile: Profile) -> String {
        PromptComposer.markdown(
            session: session,
            profile: profile,
            calendar: Calendar(identifier: .gregorian),
            locale: locale,
            timeZone: timeZone
        )
    }

    private func makeSession(
        provenance: Provenance = Provenance(
            application: ApplicationIdentity(name: "Helium", bundleID: "com.example.helium"),
            windowTitle: "Page title",
            url: URL(string: "https://example.com/article"),
            workingDirectory: URL(fileURLWithPath: "/tmp/project")
        )
    ) -> Session {
        Session(
            name: "Reading",
            entries: [
                Annotation(
                    subject: .selection(quote: "First line\nSecond line\n\nFourth line"),
                    note: "Response to selection",
                    provenance: provenance,
                    createdAt: date
                ),
                Annotation(
                    subject: .standalone,
                    note: "A standalone thought",
                    provenance: provenance,
                    createdAt: date
                ),
            ],
            createdAt: date
        )
    }
}
