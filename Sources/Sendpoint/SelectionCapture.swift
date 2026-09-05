import AppKit
import ApplicationServices

struct CapturedSelection: Equatable {
    var text: String
    var appName: String?
    var appBundleID: String?
    var processIdentifier: pid_t = 0
    var screenRect: CGRect?
}

/// Reads whatever the user has highlighted in the frontmost app.
///
/// Two strategies, in order:
///  1. Accessibility: ask the focused element for `AXSelectedText`. Silent and
///     leaves the clipboard alone, but some apps (many Electron ones, Chrome
///     with web accessibility off) do not answer.
///  2. Synthesise ⌘C, read the pasteboard, then put the old pasteboard back.
@MainActor
enum SelectionCapture {

    /// How far to go when Accessibility reports no selection.
    enum FallbackPolicy {
        /// Typed capture: the user has let go of the shortcut, so wait for the
        /// modifiers and give the app time to copy.
        case patient
        /// Hold-to-talk: the modifiers stay down by design, and no selection
        /// usually means a free-standing thought, so only glance at the clipboard.
        case brief

        var waitsForModifierRelease: Bool { self == .patient }
        var clipboardTimeout: TimeInterval { self == .patient ? 0.7 : 0.15 }
    }

    static func capture(fallback: FallbackPolicy = .patient) async throws -> CapturedSelection {
        try Task.checkCancellation()
        let app = NSWorkspace.shared.frontmostApplication
        let processIdentifier = app?.processIdentifier ?? 0
        var rect: CGRect?
        var text = ""
        defer { AutomaticSelectionMonitor.shared.discard() }

        if let (axText, axRect) = accessibilitySelection() {
            text = axText
            rect = axRect
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let automatic = AutomaticSelectionMonitor.shared.takeSelection(for: processIdentifier) {
                text = automatic
            } else {
                text = try await copyViaKeystroke(processIdentifier: processIdentifier, fallback: fallback)
                    ?? AutomaticSelectionMonitor.shared.takeSelection(for: processIdentifier) ?? ""
            }
        }
        try Task.checkCancellation()

        return CapturedSelection(
            text: text,
            appName: app?.localizedName,
            appBundleID: app?.bundleIdentifier,
            processIdentifier: app?.processIdentifier ?? 0,
            screenRect: rect
        )
    }

    // MARK: - Accessibility

    private static func accessibilitySelection() -> (String, CGRect?)? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String, !text.isEmpty
        else { return nil }

        return (text, selectionRect(of: element))
    }

    /// Screen rect of the highlighted range, so the panel can appear beside it.
    private static func selectionRect(of element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue, &boundsRef
        ) == .success, let boundsValue = boundsRef, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0
        else { return nil }
        return rect // top-left origin, Quartz screen coordinates
    }

    // MARK: - Clipboard fallback

    private static func copyViaKeystroke(
        processIdentifier: pid_t,
        fallback: FallbackPolicy
    ) async throws -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount

        if fallback.waitsForModifierRelease { try await waitForModifierRelease() }
        try Task.checkCancellation()
        postCommandKey(
            8,
            processIdentifier: processIdentifier > 0 ? processIdentifier : nil
        ) // kVK_ANSI_C

        var copiedChangeCount: Int?
        var result: String?
        let deadline = Date().addingTimeInterval(fallback.clipboardTimeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCountBeforeCopy {
                copiedChangeCount = pasteboard.changeCount
                result = pasteboard.string(forType: .string)
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        // Do not overwrite clipboard data changed after the copy we observed.
        if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
            restore(saved, to: pasteboard)
        }
        return result
    }

    /// Sends ⌘V to the app that was frontmost when export began.
    static func paste(into processIdentifier: pid_t, expectedRevision: Int) async throws -> Bool {
        guard processIdentifier > 0 else { return false }
        try await waitForModifierRelease()
        try Task.checkCancellation()
        guard NSPasteboard.general.changeCount == expectedRevision else { return false }
        postCommandKey(9, processIdentifier: processIdentifier)  // kVK_ANSI_V
        return true
    }

    /// A synthetic ⌘-key event inherits whatever modifiers are physically held.
    /// The hotkey that triggered us is ⌃⌘-something, so firing straight away
    /// makes the target app see ⌃⌘C or ⌃⌘V — neither of which is copy or paste.
    /// Wait for the user's fingers to come off first.
    private static func waitForModifierRelease(timeout: TimeInterval = 0.7) async throws {
        let watched: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(watched).isEmpty { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Diag.log("waitForModifierRelease timed out, flags still \(NSEvent.modifierFlags.rawValue)")
    }

    private static func postCommandKey(_ key: CGKeyCode, processIdentifier: pid_t? = nil) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval
        )
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        if let processIdentifier {
            down?.postToPid(processIdentifier)
            up?.postToPid(processIdentifier)
        } else {
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(_ pb: NSPasteboard) -> PasteboardSnapshot {
        (pb.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { type in item.data(forType: type).map { (type, $0) } },
                       uniquingKeysWith: { $1 })
        }
    }

    private static func restore(_ snapshot: PasteboardSnapshot, to pb: NSPasteboard) {
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        pb.writeObjects(snapshot.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }
}
