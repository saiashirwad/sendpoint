import XCTest
import SendpointDomain

final class TemplateTests: XCTestCase {
    func testBuiltInsKeepStableIDsAndDefaultToClearing() {
        XCTAssertEqual(Template.builtIns.map(\.name), ["Plain", "Learn", "Steer"])
        XCTAssertEqual(Template.builtIns.map { $0.id.uuidString }, [
            "00000000-0000-0000-0000-000000000003",
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
        ])
        XCTAssertTrue(Template.builtIns.allSatisfy(\.clearStackAfterExport))
        XCTAssertFalse(Template.builtIns.contains { $0.includeNoteNumbers })
        XCTAssertEqual(Template.plain.preamble, "")
    }

    func testNewTemplatesDefaultToClearingButCanOptOut() {
        let template = Template(name: "Custom", preamble: "", includeTimestamps: false,
                                includeHeading: false, includeNoteNumbers: false)
        XCTAssertTrue(template.clearStackAfterExport)
        let optedOut = Template(name: "Custom", preamble: "", includeTimestamps: false,
                                includeHeading: false, includeNoteNumbers: false,
                                clearStackAfterExport: false)
        XCTAssertFalse(optedOut.clearStackAfterExport)
    }

    func testLearnPreambleMatchesRequestedTextWithoutTheTemplateHeading() {
        XCTAssertEqual(Template.learn.preamble, """
        Below are notes I spoke out loud while reading. Each is either a passage I quoted followed by my reaction, or a standalone thought. They're transcribed speech, so expect loose phrasing, half-finished sentences and transcription errors.

        I'm saying these to understand the material, not just to get answers. Read them as a record of how I'm thinking:
        - Where I've got it right, say so briefly and move on.
        - Where I'm wrong or incomplete, show exactly where my reasoning went off and what's actually true.
        - Answer my questions using the mental model I'm already using, then extend it.
        - Point out anything important I seem to have missed.

        Write one connected response, not a reply to each note in turn. Organize it however explains it best, even if that's not the order of my notes. Restate what you're responding to so I don't have to scroll back.
        """)
    }

    func testSteerPreambleMatchesRequestedTextWithoutTheTemplateHeading() {
        XCTAssertEqual(Template.steer.preamble, """
        These are my notes on your previous response. Each quote is something you wrote, followed by my reaction: agreement, a question, an objection, or a change I want. Notes without a quote are general thoughts. They're transcribed speech, so read for intent.

        Treat them as direction. Answer my questions, push back where you think I'm wrong, and say what you'd change as a result. Keep it tight. Don't act on anything yet; we'll keep going until we agree.
        """)
    }
}
