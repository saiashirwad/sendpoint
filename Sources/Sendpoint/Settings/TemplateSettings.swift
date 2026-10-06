import Foundation
import Observation
import SendpointDomain

@Observable
final class TemplateSettings {
    private enum Key {
        static let templates = "templates"
        static let activeTemplateID = "activeTemplateID"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: () -> Void = {}
    private(set) var workspace: TemplateWorkspace

    var templates: [Template] { workspace.collection.templates }
    var activeTemplateID: UUID { workspace.collection.activeTemplateID }
    var activeTemplate: Template { workspace.collection.activeTemplate }
    var draft: Template { workspace.session?.draft ?? activeTemplate }
    var pendingDestination: TemplateDestination? { workspace.session?.pendingDestination }
    var isDirty: Bool { workspace.isDirty }
    var canDelete: Bool { templates.count > 1 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Key.templates)
            .flatMap { try? JSONDecoder().decode([Template].self, from: $0) }
        workspace = TemplateWorkspace(collection: TemplateCollection(
            restoring: decoded,
            activeTemplateID: defaults.string(forKey: Key.activeTemplateID).flatMap(UUID.init(uuidString:))
        ))
        persistTemplates()
        persistActiveTemplateID()
    }

    func template(id: UUID) -> Template? { workspace.collection.template(id: id) }

    func validatedNewName(_ name: String) throws -> String {
        try workspace.collection.validatedName(name)
    }

    @discardableResult
    func send(_ event: TemplateWorkspaceEvent) -> Result<TemplateWorkspaceOutcome, TemplateWorkspaceError> {
        var candidate = workspace
        let result = candidate.update(event)
        guard candidate != workspace else { return result }
        let templatesChanged = candidate.collection.templates != templates
        let selectionChanged = candidate.collection.activeTemplateID != activeTemplateID
        workspace = candidate
        if templatesChanged { persistTemplates() }
        if selectionChanged { persistActiveTemplateID() }
        if templatesChanged || selectionChanged { onChange() }
        return result
    }

    private func persistTemplates() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: Key.templates)
    }

    private func persistActiveTemplateID() {
        defaults.set(activeTemplateID.uuidString, forKey: Key.activeTemplateID)
    }
}
