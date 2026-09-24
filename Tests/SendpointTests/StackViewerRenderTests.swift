import AppKit
import SendpointDomain
import SwiftUI
import XCTest
@testable import Sendpoint

@MainActor
final class StackViewerRenderTests: XCTestCase {
    func testRenderTheViewerForEachStack() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SENDPOINT_RENDER_DIR"] else {
            throw XCTSkip("Set SENDPOINT_RENDER_DIR to produce manual review images.")
        }
        func notes(_ count: Int) -> [Note] {
            (0..<count).map { Note(subject: .standalone, body: "Note \($0 + 1)") }
        }
        let quoted = [
            Note(subject: .selection(quote: "A short passage."), body: "This is a sound test. I'm just testing this out."),
            Note(
                subject: .selection(quote: String(repeating: "The library lends more books than it owns, and the ledger never balances. ", count: 6)),
                body: "Another sound test, another sound test, another sound test, why would you want another sound test, huh?"
            ),
        ]
        let stacks = filled([Stack(notes: quoted), Stack(), Stack(notes: notes(12)), Stack(notes: notes(1))])
        let document = StackDocument(
            stacks: stacks, currentStackID: stacks[0].id,
            lastCleared: ClearedBatch(stackID: stacks[0].id, notes: notes(3))
        )
        let store = try await StackStore(persistence: StorePersistence(load: { document }, commit: { _ in }))
        let suite = "StackViewerRenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = StackPaletteController(
            store: store, settings: TemplateSettings(defaults: defaults),
            shortcuts: ShortcutSettings(defaults: defaults),
            export: ExportController(services: ExportServices(write: { _ in 1 }, paste: { _, _ in true })),
            onSelectTemplate: { _ in }
        )
        let panel = StackPaletteWindowController.makePanel()
        let hosting = NSHostingView(rootView: StackPaletteView(model: model, noteFrames: NoteFrames()))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrameOrigin(NSPoint(x: 200, y: 200))
        defer { panel.contentView = nil; panel.close() }
        model.send(.open)
        panel.orderFrontRegardless()

        for number in 1...4 {
            store.mutate(.switchStack(stackID: stacks[number - 1].id))
            await store.waitForIdle()
            model.send(.documentChanged)
            try await Task.sleep(for: .milliseconds(500))
            let view = try XCTUnwrap(panel.contentView)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("viewer-stack-\(number).png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        model.send(.toggleOverlay(.templates))
        try await Task.sleep(for: .milliseconds(500))
        try write(try XCTUnwrap(panel.contentView), to: directory, name: "viewer-templates.png")
        model.send(.closeOverlay)
        model.send(.toggleOverlay(.actions))
        try await Task.sleep(for: .milliseconds(500))
        try write(try XCTUnwrap(panel.contentView), to: directory, name: "viewer-actions.png")

        let handle = SettingsStoreHandle()
        handle.store = store
        let shortcuts = ShortcutSettings(defaults: defaults)
        let pane = NSHostingView(rootView: SettingsStacksPane(
            shortcuts: shortcuts, storeHandle: handle,
            hotKeyRegistrar: HotKeyRegistrar(settings: shortcuts, center: HotKeyCenter(
                registerEvent: { _, _, _ in (noErr, nil) }, unregisterEvent: { _ in })),
            onSettingsChanged: {}
        ).frame(width: 720, height: 620).background(Color.white))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 720, height: 620),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = pane
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(500))
        try write(pane, to: directory, name: "settings-stacks.png")

        let editor = TemplateEditorController(settings: TemplateSettings(defaults: defaults))
        editor.send(.editPreamble("Summarise these notes."))
        let templates = NSHostingView(rootView: SettingsTemplatesPane(
            settings: AppSettings(defaults: defaults), editor: editor, onSelectTemplate: { _ in }
        ).frame(width: 720, height: 620).background(Color.white))
        window.contentView = templates
        try await Task.sleep(for: .milliseconds(500))
        try write(templates, to: directory, name: "settings-templates.png")
        editor.revert()
        try await Task.sleep(for: .milliseconds(400))
        try write(templates, to: directory, name: "settings-templates-clean.png")
        store.teardown()
    }

    private func write(_ view: NSView, to directory: String, name: String) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
