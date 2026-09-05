import Darwin
import Foundation
import SendpointDomain
import XCTest
@testable import Sendpoint

final class TerminalProvenanceTests: XCTestCase {
    private let application = CapturedApplication(
        identity: ApplicationIdentity(name: "Terminal", bundleID: "com.apple.Terminal"),
        processIdentifier: 42
    )
    private let directory = URL(fileURLWithPath: "/tmp/project")

    func testAllLiveProvidersRouteEachSupportedBundleExactlyOnce() async {
        let registrations = ProvenanceProvider.live
        let identifiers = registrations.flatMap(\.bundleIDs)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        for identifier in ["com.mitchellh.ghostty", "com.apple.Terminal",
                           "net.kovidgoyal.kitty", "net.imput.helium", "com.apple.Safari", "dev.zed.Zed"] {
            XCTAssertTrue(identifiers.contains(identifier), identifier)
        }
        let providers = registrations.enumerated().map { index, provider in
            ProvenanceProvider(bundleIDs: provider.bundleIDs) { _ in
                ProvenanceFields(windowTitle: "Provider \(index)")
            }
        }
        let probe = ProvenanceProbe(genericLookup: { _ in ProvenanceFields() }, providers: providers)
        for (index, provider) in providers.enumerated() {
            for bundleID in provider.bundleIDs {
                let captured = CapturedApplication(
                    identity: ApplicationIdentity(name: "App", bundleID: bundleID), processIdentifier: 42
                )
                let result = await probe.probe(captured)
                XCTAssertEqual(result.windowTitle, "Provider \(index)", bundleID)
            }
        }
    }

    func testCancellationDuringProviderRejectsItsFields() async {
        let probe = ProvenanceProbe(
            genericLookup: { _ in ProvenanceFields(windowTitle: "Baseline") },
            providers: [ProvenanceProvider(bundleIDs: ["com.apple.Terminal"]) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return ProvenanceFields(windowTitle: "Late result")
            }]
        )
        let result = await probe.probe(application)
        XCTAssertEqual(result.windowTitle, "Baseline")
    }

    func testTerminalUsesSelectedTTYAndChecksSessionAgain() async throws {
        let snapshot = session()
        let renamed = TerminalSessionSnapshot(values: ["window", "pane", "Running", "/dev/ttys123"])!
        let reads = Sequence<TerminalSessionSnapshot?>([snapshot, renamed])
        let lookup = TerminalSessionLookup(
            readSession: { _ in await reads.next() },
            directoryForTTY: { tty, app in
                XCTAssertEqual(tty, "/dev/ttys123")
                XCTAssertEqual(app.processIdentifier, 42)
                return URL(fileURLWithPath: "/tmp/project")
            }
        )
        let fields = try await lookup.fields(for: application)
        XCTAssertEqual(fields, ProvenanceFields(windowTitle: "Running", workingDirectory: directory))
        let remaining = await reads.remaining
        XCTAssertEqual(remaining, 0)
    }

    func testSessionSwitchAndCloseRejectResult() async throws {
        for changed in [session(id: "other"), nil] {
            let reads = Sequence<TerminalSessionSnapshot?>([session(), changed])
            let lookup = TerminalSessionLookup(
                readSession: { _ in await reads.next() },
                directoryForTTY: { _, _ in URL(fileURLWithPath: "/tmp/project") }
            )
            let fields = try await lookup.fields(for: application)
            XCTAssertEqual(fields, ProvenanceFields())
        }
    }

    func testMissingSessionDoesNotInspectProcesses() async throws {
        let lookup = TerminalSessionLookup(
            readSession: { _ in nil },
            directoryForTTY: { _, _ in XCTFail("No session"); return nil }
        )
        let fields = try await lookup.fields(for: application)
        XCTAssertEqual(fields, ProvenanceFields())
        XCTAssertNil(TerminalSessionSnapshot(values: ["window", "pane"]))
    }

    func testCancellationAfterTTYLookupDoesNotReadAnotherSession() async {
        let reads = Sequence<TerminalSessionSnapshot?>([session(), session()])
        let lookup = TerminalSessionLookup(
            readSession: { _ in await reads.next() },
            directoryForTTY: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return URL(fileURLWithPath: "/tmp/project")
            }
        )
        do {
            _ = try await lookup.fields(for: application)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let remaining = await reads.remaining
        XCTAssertEqual(remaining, 1)
    }

    func testTerminalPathsPreserveLiteralCharactersAndRejectRemoteDocuments() {
        let literal = "/tmp/a #?%\nfolder "
        XCTAssertEqual(LocalFileLocation.absolutePath(literal)?.path, literal)
        for invalid in ["relative", "~/project", "https://example.com", "//server/share", "/tmp/\0bad"] {
            XCTAssertNil(LocalFileLocation.absolutePath(invalid))
        }
        for document in ["file:///tmp/project", "file://my-mac/tmp/project", "file://LOCALHOST/tmp/project"] {
            XCTAssertEqual(LocalFileLocation.documentURL(document, localHosts: ["my-mac", "localhost"]), directory)
        }
        for document in ["file://remote/tmp/project", "file://user@my-mac/tmp/project", "file:///tmp/project?q=1", "file:///tmp/%00", "https://my-mac/tmp/project"] {
            XCTAssertNil(LocalFileLocation.documentURL(document, localHosts: ["my-mac"]))
        }
    }

    func testProcessSelectionRequiresMatchingTTYAncestryAndForegroundGroup() {
        func process(_ pid: pid_t, parent: pid_t, tty: UInt32 = 12, group: UInt32 = 100, foreground: UInt32 = 100) -> TerminalProcessSnapshot {
            TerminalProcessSnapshot(pid: pid, parentPID: parent, processGroup: group,
                                    foregroundGroup: foreground, ttyDevice: tty,
                                    startedAtSeconds: 1, startedAtMicroseconds: 0)
        }
        let processes = [
            process(50, parent: 42, tty: .max, group: 50, foreground: 0), // root login ancestry
            process(100, parent: 50), process(101, parent: 100), // foreground pipeline
            process(102, parent: 50, group: 102), // background job
            process(103, parent: 50, tty: 13), // another tab
            process(104, parent: 1), // unrelated/reparented
            process(105, parent: 106), process(106, parent: 105), // corrupt cycle
        ]
        let selected = TerminalProcessSelection.foregroundProcesses(in: processes, ttyDevice: 12, applicationPID: 42)
        XCTAssertEqual(selected.map(\.pid), [100, 101])
        XCTAssertEqual(TerminalProcessSelection.agreedDirectory([directory, directory]), directory)
        XCTAssertNil(TerminalProcessSelection.agreedDirectory([directory, nil]))
        XCTAssertNil(TerminalProcessSelection.agreedDirectory([directory, URL(fileURLWithPath: "/other")]))
        XCTAssertNil(TerminalProcessSelection.agreedDirectory([]))
    }

    func testAppleScriptListsPreserveEscapesAndRejectMalformedResponses() async throws {
        let output = try await ProvenanceCommand.output(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-s", "s", "-e", #"return {"line 1" & linefeed & "line 2", "quote\"\\path", "", "a,b{}", "世界"}"#]
        )
        XCTAssertEqual(AppleScriptListParser.values(from: String(decoding: output, as: UTF8.self)),
                       ["line 1\nline 2", "quote\"\\path", "", "a,b{}", "世界"])
        for invalid in ["missing value", "{\"valid\", missing value}", "{\"unterminated}", "{\"value\",}", "{} trailing", "{42}"] {
            XCTAssertNil(AppleScriptListParser.values(from: invalid), invalid)
        }
        XCTAssertEqual(AppleScriptListParser.values(from: "{}\n"), [])
    }

    func testKittyUsesOnlyAnUnambiguousMatchedPane() throws {
        let selected = try XCTUnwrap(KittyWindowParser.selection(from: kittyJSON()))
        XCTAssertEqual(selected.cwd, "/tmp/project")
        XCTAssertEqual(selected.paneID, 3)
        XCTAssertNil(try KittyWindowParser.selection(from: Data("[]".utf8)))
        XCTAssertNil(try KittyWindowParser.selection(from: kittyJSON(extraPane: true)))
        XCTAssertThrowsError(try KittyWindowParser.selection(from: Data("invalid".utf8)))
    }

    func testKittyLookupRejectsPaneSwitchAndFallsBackForUnavailableSockets() async throws {
        let stable = kittyJSON()
        let switched = kittyJSON(paneID: 9)
        let renamed = Data(String(decoding: stable, as: UTF8.self).replacingOccurrences(of: "Shell", with: "Running").utf8)
        for (response, expected) in [(stable, directory as URL?), (renamed, directory as URL?), (switched, nil)] {
            let reads = Sequence<Data>([stable, response])
            let lookup = KittyProvenanceLookup(
                socketPaths: { _ in ["/tmp/kitty"] },
                readWindows: { _, _ in await reads.next() }
            )
            let fields = try await lookup.fields(for: application)
            XCTAssertEqual(fields.workingDirectory, expected)
        }
        let unavailable = KittyProvenanceLookup(
            socketPaths: { _ in ["/tmp/unrelated"] },
            readWindows: { _, _ in throw CocoaError(.fileReadNoSuchFile) }
        )
        let fields = try await unavailable.fields(for: application)
        XCTAssertEqual(fields, ProvenanceFields())
    }

    func testKittyCancellationStopsBeforeSecondRead() async {
        let data = kittyJSON()
        let lookup = KittyProvenanceLookup(
            socketPaths: { _ in ["/tmp/kitty"] },
            readWindows: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return data
            }
        )
        do {
            _ = try await lookup.fields(for: application)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSocketDiscoveryParsesNULRecordsAndDeduplicates() {
        let output = "p42\0\nf4\0n->0x1234\0\nf7\0n/tmp/kitty socket\0\nf8\0n/tmp/kitty socket\0\nf9\0n/tmp/new\nline\0\n"
        XCTAssertEqual(KittySocketParser.paths(from: Data(output.utf8)), ["/tmp/kitty socket", "/tmp/new\nline"])
    }

    private func session(id: String = "pane") -> TerminalSessionSnapshot {
        TerminalSessionSnapshot(values: ["window", id, "Shell", "/dev/ttys123"])!
    }

    private func kittyJSON(paneID: Int = 3, extraPane: Bool = false) -> Data {
        let pane = "{\"id\":\(paneID),\"pid\":123,\"title\":\"Shell\",\"cwd\":\"/tmp/project\"}"
        return Data("[{\"id\":1,\"tabs\":[{\"id\":2,\"windows\":[\(pane)\(extraPane ? "," + pane : "")]}]}]".utf8)
    }

    private actor Sequence<Value: Sendable> {
        var values: [Value]
        init(_ values: [Value]) { self.values = values }
        func next() -> Value { values.removeFirst() }
        var remaining: Int { values.count }
    }
}
