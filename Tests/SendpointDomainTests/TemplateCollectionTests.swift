import Foundation
import XCTest
import SendpointDomain

final class TemplateCollectionTests: XCTestCase {
    func testInvalidRestorationFallsBackAsAWholeAndDiscardsRequestedSelection() {
        var blank = Template.plain
        blank.name = " \n "
        var untrimmed = Template.plain
        untrimmed.name = " Plain "
        let duplicateName = template(name: "Ｌｅáｒｎ")
        let duplicateID = template(id: Template.learn.id, name: "Different")
        for stored: [Template]? in [nil, [], [blank], [untrimmed], [.learn, duplicateName], [.learn, duplicateID]] {
            let collection = TemplateCollection(restoring: stored, activeTemplateID: Template.learn.id)
            XCTAssertEqual(collection.templates, Template.builtIns)
            XCTAssertEqual(collection.activeTemplate, .plain)
        }
    }

    func testRestorationPreservesEditedBuiltInsCustomOrderAndValidActiveTemplate() {
        var edited = Template.learn
        edited.name = "Edited"
        edited.preamble = "Keep my changes"
        let first = template(name: "First custom")
        let second = template(name: "Second custom")
        let collection = TemplateCollection(
            restoring: [first, .steer, edited, second], activeTemplateID: first.id
        )
        XCTAssertEqual(collection.templates, [edited, .steer, first, second])
        XCTAssertEqual(collection.activeTemplate, first)
        let repaired = TemplateCollection(restoring: [first, .steer, edited], activeTemplateID: UUID())
        XCTAssertEqual(repaired.activeTemplate, edited)
    }

    func testAddingAndUpdatingTrimNamesWithoutChangingSelection() throws {
        var collection = TemplateCollection()
        var custom = template(name: "  Custom  ")
        try collection.add(custom)
        XCTAssertEqual(collection.activeTemplate, .plain)
        XCTAssertEqual(collection.template(id: custom.id)?.name, "Custom")
        try collection.select(id: custom.id)
        custom.name = "  Renamed\n"
        custom.preamble = "Updated content"
        try collection.update(custom)
        XCTAssertEqual(collection.activeTemplateID, custom.id)
        XCTAssertEqual(collection.activeTemplate.name, "Renamed")
        XCTAssertEqual(collection.activeTemplate.preamble, "Updated content")
    }

    func testRejectedMutationsLeaveCollectionUntouched() throws {
        var collection = TemplateCollection()
        let original = collection
        let duplicate = template(id: Template.plain.id, name: "Different name")
        XCTAssertThrowsError(try collection.add(duplicate)) {
            XCTAssertEqual($0 as? TemplateError, .duplicateID)
        }
        XCTAssertEqual(collection, original)
        XCTAssertThrowsError(try collection.add(template(name: "lEárN"))) {
            XCTAssertEqual($0 as? TemplateError, .duplicateName)
        }
        XCTAssertEqual(collection, original)
        var invalid = Template.plain
        invalid.name = " \n "
        XCTAssertThrowsError(try collection.update(invalid)) {
            XCTAssertEqual($0 as? TemplateError, .emptyName)
        }
        XCTAssertEqual(collection, original)
        invalid.name = "Learn"
        XCTAssertThrowsError(try collection.update(invalid)) {
            XCTAssertEqual($0 as? TemplateError, .duplicateName)
        }
        XCTAssertEqual(collection, original)
        XCTAssertThrowsError(try collection.select(id: UUID())) {
            XCTAssertEqual($0 as? TemplateError, .unknownTemplate)
        }
        XCTAssertThrowsError(try collection.update(template(name: "Unknown"))) {
            XCTAssertEqual($0 as? TemplateError, .unknownTemplate)
        }
        XCTAssertThrowsError(try collection.delete(id: UUID())) {
            XCTAssertEqual($0 as? TemplateError, .unknownTemplate)
        }
        XCTAssertEqual(collection, original)
    }

    func testDeletingActiveChoosesNextThenPreviousAndCannotRemoveLast() throws {
        var collection = TemplateCollection()
        try collection.select(id: Template.learn.id)
        try collection.delete(id: Template.learn.id)
        XCTAssertEqual(collection.activeTemplate, .steer)
        try collection.delete(id: Template.steer.id)
        XCTAssertEqual(collection.activeTemplate, .plain)
        let remaining = collection
        XCTAssertThrowsError(try collection.delete(id: Template.plain.id)) {
            XCTAssertEqual($0 as? TemplateError, .lastTemplate)
        }
        XCTAssertEqual(collection, remaining)
    }

    func testDeletingInactiveKeepsSelectionAndUnchangedMutationsAreNoOps() throws {
        var collection = TemplateCollection()
        let original = collection
        try collection.select(id: Template.plain.id)
        try collection.update(.plain)
        XCTAssertEqual(collection, original)
        try collection.delete(id: Template.learn.id)
        XCTAssertEqual(collection.activeTemplate, .plain)
        XCTAssertEqual(try collection.validatedName("  plain  ", excluding: Template.plain.id), "plain")
    }

    private func template(id: UUID = UUID(), name: String) -> Template {
        Template(id: id, name: name, preamble: "", includeTimestamps: false, includeHeading: false,
                includeNoteNumbers: false, clearStackAfterExport: false)
    }
}
