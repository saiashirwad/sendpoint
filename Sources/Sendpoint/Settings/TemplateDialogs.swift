import AppKit
import SendpointDomain

enum TemplateDialogs {
    static func request(_ destination: TemplateDestination, in editor: TemplateSettings) -> Bool {
        do {
            let outcome = try editor.send(.request(destination)).get()
            guard outcome == .needsDecision else { return true }
            let decision = dirtyDecision(for: editor) ?? .cancel
            return try editor.send(.resolve(decision)).get() != .cancelled
        } catch {
            showError(error)
            return false
        }
    }

    static func delete(_ editor: TemplateSettings) {
        let stored = editor.activeTemplate
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(stored.name)”?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try editor.send(.delete).get()
        } catch {
            showError(error)
        }
    }

    static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Couldn't Change Template"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func dirtyDecision(
        for editor: TemplateSettings
    ) -> TemplateDirtyDecision? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to “\(editor.draft.name)”?"
        alert.informativeText = "Choose what to do with this template."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Save as New…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            guard let name = requestNewName(for: editor) else { return nil }
            return .saveAsNew(name: name, id: UUID())
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private static func requestNewName(for editor: TemplateSettings) -> String? {
        var proposedName = "\(editor.draft.name) Copy"
        while true {
            let alert = NSAlert()
            alert.messageText = "New Template"
            alert.informativeText = "Enter a unique template name."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            let field = NSTextField(string: proposedName)
            field.placeholderString = "Template name"
            field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            proposedName = field.stringValue
            do {
                return try editor.validatedNewName(proposedName)
            } catch {
                showError(error)
            }
        }
    }
}
