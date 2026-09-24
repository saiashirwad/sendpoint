import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class StackReadoutTests: XCTestCase {
    func testPanelFitsItsContent() async throws {
        let stacks = [
            Stack(notes: [Note(subject: .standalone, body: "One")]),
            Stack(),
            Stack(notes: (1...12).map { Note(subject: .standalone, body: "\($0)") }),
        ]
        let document = StackDocument(stacks: filled(stacks), currentStackID: stacks[0].id)
        let store = try await StackStore(persistence: StorePersistence(
            load: { document }, commit: { _ in }
        ))
        let controller = StackReadoutController(store: store)
        defer { controller.teardown() }

        for number in [2, 3] {
            controller.show(number: number)
            let panel = controller.panel
            let hosting = try XCTUnwrap(panel.contentView)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.size.width, hosting.fittingSize.width, accuracy: 0.5)
            XCTAssertEqual(panel.frame.size.height, hosting.fittingSize.height, accuracy: 0.5)
            XCTAssertGreaterThan(panel.frame.width, 200)
        }
    }
}
