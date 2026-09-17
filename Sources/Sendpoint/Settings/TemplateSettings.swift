import Foundation
import Observation
import SendpointDomain

@Observable
final class TemplateSettings {
    private enum Key {
        static let templates = "templates"
        static let activeTemplateID = "activeTemplateID"
    }

    private let defaults: UserDefaults
    private var collection: TemplateCollection

    var templates: [Template] { collection.templates }
    var activeTemplateID: UUID { collection.activeTemplateID }
    var activeTemplate: Template { collection.activeTemplate }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Key.templates)
            .flatMap { try? JSONDecoder().decode([Template].self, from: $0) }
        collection = TemplateCollection(
            restoring: decoded,
            activeTemplateID: defaults.string(forKey: Key.activeTemplateID).flatMap(UUID.init(uuidString:))
        )
        persistTemplates()
        persistActiveTemplateID()
    }

    func selectTemplate(id: UUID) throws { try change { try $0.select(id: id) } }
    func updateTemplate(_ template: Template) throws { try change { try $0.update(template) } }
    func addTemplate(_ template: Template) throws { try change { try $0.add(template) } }

    /// Removes a template and returns the ID that is active afterwards.
    func deleteTemplate(id: UUID) throws -> UUID {
        try change { try $0.delete(id: id) }
        return activeTemplateID
    }

    func template(id: UUID) -> Template? { collection.template(id: id) }

    func validatedName(_ proposedName: String, excluding templateID: UUID?) throws -> String {
        try collection.validatedName(proposedName, excluding: templateID)
    }

    private func change(_ mutation: (inout TemplateCollection) throws -> Void) throws {
        var candidate = collection
        try mutation(&candidate)
        guard candidate != collection else { return }
        let templatesChanged = candidate.templates != templates
        let selectionChanged = candidate.activeTemplateID != activeTemplateID
        collection = candidate
        if templatesChanged { persistTemplates() }
        if selectionChanged { persistActiveTemplateID() }
    }

    private func persistTemplates() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: Key.templates)
    }

    private func persistActiveTemplateID() {
        defaults.set(activeTemplateID.uuidString, forKey: Key.activeTemplateID)
    }
}
