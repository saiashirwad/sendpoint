import Foundation
import XCTest
import SendpointDomain

final class TemplateCollectionTests: XCTestCase {
    func testInvalidRestorationFallsBackAsAWholeAndDiscardsRequestedSelection() {
        var blank = Template.plain
        blank.name = " \n "
        var untrimmed = Template.plain
        untrimmed.name = " Plain "
        let duplicateName = template(name: "ＣｏｈÉｒｅｎｔ")
        let duplicateID = template(id: Template.coherent.id, name: "Different")
        for stored: [Template]? in [nil, [], [blank], [untrimmed], [.coherent, duplicateName], [.coherent, duplicateID]] {
            let collection = TemplateCollection(restoring: stored, activeTemplateID: Template.coherent.id)
            XCTAssertEqual(collection.templates, Template.builtIns)
            XCTAssertEqual(collection.activeTemplate, .plain)
        }
    }

    func testRestorationPreservesEditedBuiltInsCustomOrderAndValidActiveTemplate() {
        var edited = Template.coherent
        edited.name = "Edited"
        edited.preamble = "Keep my changes"
        let first = template(name: "First custom")
        let second = template(name: "Second custom")
        let collection = TemplateCollection(
            restoring: [first, .pointByPoint, edited, second], activeTemplateID: first.id
        )
        XCTAssertEqual(collection.templates, [edited, .pointByPoint, first, second])
        XCTAssertEqual(collection.activeTemplate, first)
        let repaired = TemplateCollection(restoring: [first, .pointByPoint, edited], activeTemplateID: UUID())
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
        XCTAssertThrowsError(try collection.add(template(name: "cOhÉrEnt"))) {
            XCTAssertEqual($0 as? TemplateError, .duplicateName)
        }
        XCTAssertEqual(collection, original)
        var invalid = Template.plain
        invalid.name = " \n "
        XCTAssertThrowsError(try collection.update(invalid)) {
            XCTAssertEqual($0 as? TemplateError, .emptyName)
        }
        XCTAssertEqual(collection, original)
        invalid.name = "Coherent"
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
        try collection.select(id: Template.coherent.id)
        try collection.delete(id: Template.coherent.id)
        XCTAssertEqual(collection.activeTemplate, .pointByPoint)
        try collection.delete(id: Template.pointByPoint.id)
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
        try collection.delete(id: Template.coherent.id)
        XCTAssertEqual(collection.activeTemplate, .plain)
        XCTAssertEqual(try collection.validatedName("  plain  ", excluding: Template.plain.id), "plain")
    }

    private func template(id: UUID = UUID(), name: String) -> Template {
        Template(id: id, name: name, preamble: "", includeTimestamps: false, includeHeading: false,
                includeNoteNumbers: false, clearStackAfterExport: false)
    }
}
