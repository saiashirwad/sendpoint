import AppKit
import ApplicationServices
import Carbon.HIToolbox

nonisolated struct CapturedSelection: Equatable {
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
///
/// Tests substitute the two closures; `live` binds the real monitor and pasteboard.
struct SelectionCapture {
    /// `editorMayOpen` is called when the front app no longer needs to be
    /// frontmost: at once when Accessibility answered, or just after the copy
    /// keystroke has been delivered. The clipboard may still be read after.
    var read: (FallbackPolicy, _ editorMayOpen: @escaping @MainActor @Sendable () -> Void) async throws -> CapturedSelection
    /// Sends ⌘V to the app that was frontmost when export began.
    var paste: (_ processIdentifier: pid_t, _ expectedRevision: Int) async throws -> Bool

    static func live(monitor: AutomaticSelectionMonitor, pasteboard: NSPasteboard = .general) -> Self {
        Self(
            read: { fallback, editorMayOpen in
                try await capture(monitor: monitor, pasteboard: pasteboard,
                    fallback: fallback, editorMayOpen: editorMayOpen)
            },
            paste: { processIdentifier, expectedRevision in
                try await paste(into: processIdentifier, expectedRevision: expectedRevision,
                    pasteboard: pasteboard)
            }
        )
    }

    /// How far to go when Accessibility reports no selection.
    enum FallbackPolicy {
        /// Typed capture: the user has let go of the shortcut, so wait for the
        /// modifiers and give the app time to copy.
        case patient
        /// Hold-to-talk: the modifiers stay down by design, and no selection
        /// usually means a free-standing thought, so only glance at the clipboard.
        case brief

        var waitsForModifierRelease: Bool { self == .patient }
        /// A real copy lands well under 100ms; the rest is slack for a busy app.
        var clipboardTimeout: TimeInterval { self == .patient ? 0.3 : 0.15 }
    }

    /// What the focused element said when asked for its selection.
    private enum AccessibilityAnswer {
        case text(String, CGRect?)
        /// The element handles text selection and reports none. Nothing to
        /// copy, so the clipboard fallback would only wait out its timeout.
        case empty
        /// No focused element, or one that does not speak the text protocol.
        case unavailable
    }

    private static func capture(
        monitor: AutomaticSelectionMonitor,
        pasteboard: NSPasteboard,
        fallback: FallbackPolicy,
        editorMayOpen: @escaping @MainActor @Sendable () -> Void
    ) async throws -> CapturedSelection {
        try Task.checkCancellation()
        let app = NSWorkspace.shared.frontmostApplication
        let processIdentifier = app?.processIdentifier ?? 0
        var rect: CGRect?
        var text = ""
        defer { monitor.discard() }

        var answer = accessibilitySelection()
        if case let .text(axText, axRect) = answer {
            text = axText
            rect = axRect
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { answer = .unavailable }
        }
        if case .unavailable = answer {
            if let automatic = monitor.takeSelection(for: processIdentifier) {
                text = automatic
            } else {
                text = try await copyViaKeystroke(pasteboard: pasteboard, processIdentifier: processIdentifier,
                    fallback: fallback, afterKeystroke: editorMayOpen)
                    ?? monitor.takeSelection(for: processIdentifier) ?? ""
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

    private static func accessibilitySelection() -> AccessibilityAnswer {
        guard AXIsProcessTrusted() else { return .unavailable }
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return .unavailable }
        let element = focused as! AXUIElement

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String
        else { return .unavailable }
        if text.isEmpty {
            // An empty string alone is not proof: some views answer "" for
            // any selection. A zero-length range inside real text is. Kitty
            // reports "", range (0,0) and zero characters no matter what is
            // highlighted, so an element that claims to hold no text at all
            // still goes to the clipboard fallback.
            let holdsText = (characterCount(of: element) ?? 0) > 0
            return holdsText && selectedRangeLength(of: element) == 0 ? .empty : .unavailable
        }

        return .text(text, selectionRect(of: element))
    }

    private static func characterCount(of element: AXUIElement) -> Int? {
        var countRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countRef) == .success
        else { return nil }
        return countRef as? Int
    }

    private static func selectedRangeLength(of element: AXUIElement) -> Int? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range.length
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

    /// How long the target app gets to take the copy keystroke before the
    /// editor is allowed to come forward. Key events are handled well inside
    /// this in any responsive app; the clipboard poll continues regardless.
    private static let keystrokeSettleTime: Duration = .milliseconds(40)

    private static func copyViaKeystroke(
        pasteboard: NSPasteboard,
        processIdentifier: pid_t,
        fallback: FallbackPolicy,
        afterKeystroke: @escaping @MainActor @Sendable () -> Void
    ) async throws -> String? {
        let saved = snapshot(pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount

        if fallback.waitsForModifierRelease { try await waitForModifierRelease() }
        try Task.checkCancellation()
        postCommandKey(
            CGKeyCode(kVK_ANSI_C),
            processIdentifier: processIdentifier > 0 ? processIdentifier : nil
        )

        var copiedChangeCount: Int?
        var result: String?
        let deadline = Date().addingTimeInterval(fallback.clipboardTimeout)
        try await Task.sleep(for: keystrokeSettleTime)
        try Task.checkCancellation()
        afterKeystroke()
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

    private static func paste(into processIdentifier: pid_t, expectedRevision: Int,
                              pasteboard: NSPasteboard) async throws -> Bool {
        guard processIdentifier > 0 else { return false }
        try await waitForModifierRelease()
        try Task.checkCancellation()
        guard pasteboard.changeCount == expectedRevision else { return false }
        postCommandKey(CGKeyCode(kVK_ANSI_V), processIdentifier: processIdentifier)
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
