import AppKit
import SendpointDomain
import XCTest
@testable import Sendpoint

@MainActor
final class StackCycleWindowTests: XCTestCase {
    func testCycleReusesPaletteAndExternalDismissalCancelsOnce() async throws {
        _ = NSApplication.shared
        let first = Stack(name: "Default", notes: [Note(subject: .standalone, body: "A saved note")])
        let second = Stack(name: "Research", notes: [
            Note(subject: .selection(quote: "A shared view for browsing and switching."),
                 body: "Preview each stack while holding Command, then release to choose it."),
            Note(subject: .standalone, body: "Keep the stack list in a consistent order."),
        ])
        let document = StackDocument(stacks: [first, second], currentStackID: first.id)
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        let suite = "StackCycleWindowTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let surfaces = SurfaceCoordinator(hasModalWindow: { false })
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = StackPaletteWindowController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults), voiceSettings: VoiceSettings(defaults: defaults),
            export: ExportController(services: ExportServices(write: { _ in nil }, paste: { _, _ in false })),
            surfaces: surfaces, onSelectTemplate: { _ in }
        )
        defer { controller.teardown() }
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) && $0.title == "Stacks" })
        var cancelled = 0
        controller.onCycleClosed = { cancelled += 1 }
        controller.previewStack(second.id)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(surfaces.visible, [.switcher])
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(store.currentStack.id, first.id)

        if let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] {
            let view = try XCTUnwrap(panel.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("stack-cycle.png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        surfaces.present(.captureEditor)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(cancelled, 1)
        controller.closeCycle()
        XCTAssertEqual(cancelled, 1)

        controller.show(focus: .notes)
        XCTAssertTrue(panel.isVisible, "Browsing must reuse the same native window")
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertEqual(surfaces.visible, [.palette])
        controller.previewStack(first.id)
        XCTAssertEqual(surfaces.visible, [.switcher])
        controller.teardown()
        controller.teardown()
        controller.previewStack(second.id)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(surfaces.visible.isEmpty)
        XCTAssertEqual(cancelled, 2)
    }
}
