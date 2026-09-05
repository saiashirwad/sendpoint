import Foundation
import XCTest
import SendpointDomain
@testable import Sendpoint

final class EditorProvenanceTests: XCTestCase {
    func testEditorDocumentAndTitleYieldFileAndOutermostWorkspace() {
        let file = "/Users/reader/code/effect/packages/effect/src/Unify.ts"
        let fields = editorFields(title: "Unify.ts — effect", document: file)

        XCTAssertEqual(fields.url, URL(fileURLWithPath: file))
        XCTAssertEqual(
            fields.workingDirectory,
            URL(fileURLWithPath: "/Users/reader/code/effect")
        )
    }

    func testEditorParsesReversedDirtyProfileRemoteAndAppTitleSegments() {
        let file = "/Users/reader/code/effect/src/Unify.ts"
        let fields = editorFields(
            title: "● Unify.ts — effect [SSH: dev] — Data Science (Profile) — Visual Studio Code - Insiders",
            document: file
        )
        XCTAssertEqual(fields.url, URL(fileURLWithPath: file))
        XCTAssertEqual(fields.workingDirectory, URL(fileURLWithPath: "/Users/reader/code/effect"))

        let reversed = editorFields(
            title: "effect (Workspace) — Unify.ts — Cursor",
            document: file
        )
        XCTAssertEqual(reversed.workingDirectory, URL(fileURLWithPath: "/Users/reader/code/effect"))
    }

    func testEditorDistinguishesDirectoryDocumentAndSingleFile() {
        let directory = URL(fileURLWithPath: "/Users/reader/code/effect")
        let directoryFields = editorFields(
            title: "effect",
            document: directory.path,
            directories: [directory]
        )
        XCTAssertNil(directoryFields.url)
        XCTAssertEqual(directoryFields.workingDirectory, directory)

        let file = URL(fileURLWithPath: "/Users/reader/Desktop/notes.md")
        let fileFields = editorFields(title: "notes.md", document: file.path)
        XCTAssertEqual(fileFields.url, file)
        XCTAssertNil(fileFields.workingDirectory)
    }

    func testEditorUsesAbsoluteTitleHintButRejectsRemoteAndRelativeDocuments() {
        let file = "/Users/reader/code/effect/src/Unify.ts"
        let titleFields = editorFields(title: "\(file) - effect - Cursor", document: nil)
        XCTAssertEqual(titleFields.url, URL(fileURLWithPath: file))
        XCTAssertEqual(titleFields.workingDirectory, URL(fileURLWithPath: "/Users/reader/code/effect"))

        XCTAssertNil(editorFields(
            title: "Main.swift — project",
            document: "vscode-remote://ssh/project/Main.swift"
        ).url)
        XCTAssertNil(editorFields(
            title: "Main.swift — project",
            document: "relative/Main.swift"
        ).url)
    }

    private func editorFields(
        title: String?,
        document: String?,
        directories: [URL] = []
    ) -> ProvenanceFields {
        let paths = Set(directories.map(\.standardizedFileURL.path))
        return EditorProvenanceParser.fields(
            windowTitle: title,
            document: document,
            isDirectory: { paths.contains($0.standardizedFileURL.path) }
        )
    }
}
