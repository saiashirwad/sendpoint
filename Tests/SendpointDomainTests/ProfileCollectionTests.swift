import Foundation
import XCTest
import SendpointDomain

final class ProfileCollectionTests: XCTestCase {
    func testInvalidRestorationFallsBackAsAWholeAndDiscardsRequestedSelection() {
        var blank = Profile.plain
        blank.name = " \n "
        var untrimmed = Profile.plain
        untrimmed.name = " Plain "
        let duplicateName = profile(name: "ＣｏｈÉｒｅｎｔ")
        let duplicateID = profile(id: Profile.coherent.id, name: "Different")
        for stored: [Profile]? in [nil, [], [blank], [untrimmed], [.coherent, duplicateName], [.coherent, duplicateID]] {
            let collection = ProfileCollection(restoring: stored, activeProfileID: Profile.coherent.id)
            XCTAssertEqual(collection.profiles, Profile.builtIns)
            XCTAssertEqual(collection.activeProfile, .plain)
        }
    }

    func testRestorationPreservesEditedBuiltInsCustomOrderAndValidActiveProfile() {
        var edited = Profile.coherent
        edited.name = "Edited"
        edited.preamble = "Keep my changes"
        let first = profile(name: "First custom")
        let second = profile(name: "Second custom")
        let collection = ProfileCollection(
            restoring: [first, .pointByPoint, edited, second], activeProfileID: first.id
        )
        XCTAssertEqual(collection.profiles, [edited, .pointByPoint, first, second])
        XCTAssertEqual(collection.activeProfile, first)
        let repaired = ProfileCollection(restoring: [first, .pointByPoint, edited], activeProfileID: UUID())
        XCTAssertEqual(repaired.activeProfile, edited)
    }

    func testAddingAndUpdatingTrimNamesWithoutChangingSelection() throws {
        var collection = ProfileCollection()
        var custom = profile(name: "  Custom  ")
        try collection.add(custom)
        XCTAssertEqual(collection.activeProfile, .plain)
        XCTAssertEqual(collection.profile(id: custom.id)?.name, "Custom")
        try collection.select(id: custom.id)
        custom.name = "  Renamed\n"
        custom.preamble = "Updated content"
        try collection.update(custom)
        XCTAssertEqual(collection.activeProfileID, custom.id)
        XCTAssertEqual(collection.activeProfile.name, "Renamed")
        XCTAssertEqual(collection.activeProfile.preamble, "Updated content")
    }

    func testRejectedMutationsLeaveCollectionUntouched() throws {
        var collection = ProfileCollection()
        let original = collection
        let duplicate = profile(id: Profile.plain.id, name: "Different name")
        XCTAssertThrowsError(try collection.add(duplicate)) {
            XCTAssertEqual($0 as? ProfileMutationError, .duplicateID)
        }
        XCTAssertEqual(collection, original)
        XCTAssertThrowsError(try collection.add(profile(name: "cOhÉrEnt"))) {
            XCTAssertEqual($0 as? ProfileMutationError, .duplicateName)
        }
        XCTAssertEqual(collection, original)
        var invalid = Profile.plain
        invalid.name = " \n "
        XCTAssertThrowsError(try collection.update(invalid)) {
            XCTAssertEqual($0 as? ProfileMutationError, .emptyName)
        }
        XCTAssertEqual(collection, original)
        invalid.name = "Coherent"
        XCTAssertThrowsError(try collection.update(invalid)) {
            XCTAssertEqual($0 as? ProfileMutationError, .duplicateName)
        }
        XCTAssertEqual(collection, original)
        XCTAssertThrowsError(try collection.select(id: UUID())) {
            XCTAssertEqual($0 as? ProfileMutationError, .unknownProfile)
        }
        XCTAssertThrowsError(try collection.update(profile(name: "Unknown"))) {
            XCTAssertEqual($0 as? ProfileMutationError, .unknownProfile)
        }
        XCTAssertThrowsError(try collection.delete(id: UUID())) {
            XCTAssertEqual($0 as? ProfileMutationError, .unknownProfile)
        }
        XCTAssertEqual(collection, original)
    }

    func testDeletingActiveChoosesNextThenPreviousAndCannotRemoveLast() throws {
        var collection = ProfileCollection()
        try collection.select(id: Profile.coherent.id)
        try collection.delete(id: Profile.coherent.id)
        XCTAssertEqual(collection.activeProfile, .pointByPoint)
        try collection.delete(id: Profile.pointByPoint.id)
        XCTAssertEqual(collection.activeProfile, .plain)
        let remaining = collection
        XCTAssertThrowsError(try collection.delete(id: Profile.plain.id)) {
            XCTAssertEqual($0 as? ProfileMutationError, .lastProfile)
        }
        XCTAssertEqual(collection, remaining)
    }

    func testDeletingInactiveKeepsSelectionAndUnchangedMutationsAreNoOps() throws {
        var collection = ProfileCollection()
        let original = collection
        try collection.select(id: Profile.plain.id)
        try collection.update(.plain)
        XCTAssertEqual(collection, original)
        try collection.delete(id: Profile.coherent.id)
        XCTAssertEqual(collection.activeProfile, .plain)
        XCTAssertEqual(try collection.validatedName("  plain  ", excluding: Profile.plain.id), "plain")
    }

    private func profile(id: UUID = UUID(), name: String) -> Profile {
        Profile(id: id, name: name, preamble: "", includeApplication: false, includeWindow: false,
                includeLink: false, includeTimestamps: false, includeHeading: false, clearSessionAfterExport: false)
    }
}
