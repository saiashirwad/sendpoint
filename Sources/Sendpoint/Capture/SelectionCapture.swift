import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SendpointDomain

nonisolated struct CapturedSelection: Equatable {
    var text: String
    var screenRect: CGRect?
}

struct SelectionCapture {
    var read: (FallbackPolicy, _ editorMayOpen: @escaping @MainActor @Sendable () -> Void) async throws -> CapturedSelection
    var paste: (_ processIdentifier: pid_t, _ expectedRevision: Int) async throws -> Bool
    var insertText: (_ text: String, _ processIdentifier: pid_t) async throws -> Bool = { _, _ in false }

    static func live(monitor: AutomaticSelectionMonitor, pasteboard: NSPasteboard = .general) -> Self {
        Self(
            read: { fallback, editorMayOpen in
                try await capture(monitor: monitor, pasteboard: pasteboard,
                    fallback: fallback, editorMayOpen: editorMayOpen)
            },
            paste: { processIdentifier, expectedRevision in
                try await paste(into: processIdentifier, expectedRevision: expectedRevision,
                    pasteboard: pasteboard)
            },
            insertText: { text, processIdentifier in
                pasteboard.clearContents()
                guard pasteboard.setString(text, forType: .string) else { return false }
                let revision = pasteboard.changeCount
                try await Task.sleep(for: .milliseconds(120))
                return try await paste(into: processIdentifier, expectedRevision: revision,
                    pasteboard: pasteboard)
            }
        )
    }

    enum FallbackPolicy {
        case patient
        case brief

        var modifierReleaseTimeout: TimeInterval? { self == .patient ? 0.7 : nil }
        var clipboardTimeout: TimeInterval { self == .patient ? 0.3 : 0.15 }
    }

    private enum AccessibilityAnswer {
        case text(String, CGRect?)
        case empty
        case unavailable
    }

    private static func capture(
        monitor: AutomaticSelectionMonitor,
        pasteboard: NSPasteboard,
        fallback: FallbackPolicy,
        editorMayOpen: @escaping @MainActor @Sendable () -> Void
    ) async throws -> CapturedSelection {
        try Task.checkCancellation()
        let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        var rect: CGRect?
        var text = ""
        defer { monitor.discard() }

        var answer = accessibilitySelection()
        if case let .text(axText, axRect) = answer {
            text = axText
            rect = axRect
            if text.nonblank == nil { answer = .unavailable }
        }
        if case .unavailable = answer {
            if let automatic = monitor.takeSelection(for: processIdentifier) {
                text = automatic
            } else {
                text = try await copyViaKeystroke(pasteboard: pasteboard, processIdentifier: processIdentifier,
                    fallback: fallback, editorMayOpen: editorMayOpen)
                    ?? monitor.takeSelection(for: processIdentifier) ?? ""
            }
        }
        try Task.checkCancellation()

        return CapturedSelection(
            text: text,
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
        return rect
    }

    // MARK: - Clipboard fallback

    private static func copyViaKeystroke(
        pasteboard: NSPasteboard,
        processIdentifier: pid_t,
        fallback: FallbackPolicy,
        editorMayOpen: @escaping @MainActor @Sendable () -> Void
    ) async throws -> String? {
        let saved = snapshot(pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount

        if fallback == .patient { editorMayOpen() }
        try await waitForModifierRelease(timeout: fallback.modifierReleaseTimeout)
        try Task.checkCancellation()
        Diag.log("selection: posting copy keystroke")
        postCommandKey(
            CGKeyCode(kVK_ANSI_C),
            processIdentifier: processIdentifier > 0 ? processIdentifier : nil
        )
        if fallback == .brief { editorMayOpen() }

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

        if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
            restore(saved, to: pasteboard)
        }
        return result
    }

    private static func paste(into processIdentifier: pid_t, expectedRevision: Int,
                              pasteboard: NSPasteboard) async throws -> Bool {
        guard processIdentifier > 0 else { return false }
        try await waitForModifierRelease(timeout: 0.7)
        try Task.checkCancellation()
        guard pasteboard.changeCount == expectedRevision else { return false }
        postCommandKey(CGKeyCode(kVK_ANSI_V), processIdentifier: processIdentifier)
        return true
    }

    private static func waitForModifierRelease(timeout: TimeInterval?) async throws {
        let watched: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let deadline = timeout.map { Date().addingTimeInterval($0) } ?? .distantFuture
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
