import Foundation

public enum TemplateError: Error, Equatable, Sendable, LocalizedError {
    case unknownTemplate
    case lastTemplate
    case emptyName
    case duplicateName
    case duplicateID

    public var errorDescription: String? {
        switch self {
        case .unknownTemplate: "That template no longer exists."
        case .lastTemplate: "The last template cannot be deleted."
        case .emptyName: "Enter a template name."
        case .duplicateName: "A template with that name already exists."
        case .duplicateID: "A template with that identifier already exists."
        }
    }
}

/// A nonempty collection with unique IDs/names and an active member. Mutations
/// validate before changing anything; storage and change notifications are external.
public struct TemplateCollection: Equatable, Sendable {
    public private(set) var templates: [Template]
    public private(set) var activeTemplateID: UUID

    public var activeTemplate: Template {
        // Construction and every mutation preserve active membership.
        templates.first { $0.id == activeTemplateID }!
    }

    /// Invalid stored collections are replaced as a whole. Valid collections
    /// retain edited built-ins and custom order, with built-ins placed first.
    public init(restoring stored: [Template]? = nil, activeTemplateID requestedID: UUID? = nil) {
        guard let stored, Self.isValid(stored) else {
            templates = Template.builtIns
            activeTemplateID = Template.builtIns[0].id
            return
        }
        let builtInIDs = Template.builtIns.map(\.id)
        let ordered = builtInIDs.compactMap { id in stored.first { $0.id == id } }
            + stored.filter { !builtInIDs.contains($0.id) }
        templates = ordered
        activeTemplateID = requestedID.flatMap { id in
            ordered.contains { $0.id == id } ? id : nil
        } ?? ordered[0].id
    }

    public func template(id: UUID) -> Template? {
        templates.first { $0.id == id }
    }

    public func validatedName(_ name: String, excluding templateID: UUID? = nil) throws -> String {
        guard let trimmed = name.nonblank else { throw TemplateError.emptyName }
        let key = Self.nameKey(trimmed)
        guard !templates.contains(where: { $0.id != templateID && Self.nameKey($0.name) == key }) else {
            throw TemplateError.duplicateName
        }
        return trimmed
    }

    public mutating func select(id: UUID) throws {
        guard template(id: id) != nil else { throw TemplateError.unknownTemplate }
        activeTemplateID = id
    }

    public mutating func update(_ template: Template) throws {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else {
            throw TemplateError.unknownTemplate
        }
        var validated = template
        validated.name = try validatedName(template.name, excluding: template.id)
        templates[index] = validated
    }

    public mutating func add(_ template: Template) throws {
        guard self.template(id: template.id) == nil else { throw TemplateError.duplicateID }
        var validated = template
        validated.name = try validatedName(template.name)
        templates.append(validated)
    }

    public mutating func delete(id: UUID) throws {
        guard templates.count > 1 else { throw TemplateError.lastTemplate }
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateError.unknownTemplate
        }
        templates.remove(at: index)
        if activeTemplateID == id {
            activeTemplateID = templates[min(index, templates.count - 1)].id
        }
    }

    private static func isValid(_ templates: [Template]) -> Bool {
        guard !templates.isEmpty else { return false }
        var ids: Set<UUID> = []
        var names: Set<String> = []
        return templates.allSatisfy { template in
            template.name.nonblank == template.name
                && ids.insert(template.id).inserted
                && names.insert(nameKey(template.name)).inserted
        }
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
