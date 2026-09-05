import Foundation

public enum ProfileMutationError: Error, Equatable, Sendable, LocalizedError {
    case unknownProfile
    case lastProfile
    case emptyName
    case duplicateName
    case duplicateID

    public var errorDescription: String? {
        switch self {
        case .unknownProfile: "That template no longer exists."
        case .lastProfile: "The last template cannot be deleted."
        case .emptyName: "Enter a template name."
        case .duplicateName: "A template with that name already exists."
        case .duplicateID: "A template with that identifier already exists."
        }
    }
}

/// A nonempty collection with unique IDs/names and an active member. Mutations
/// validate before changing anything; storage and change notifications are external.
public struct ProfileCollection: Equatable, Sendable {
    public private(set) var profiles: [Profile]
    public private(set) var activeProfileID: UUID

    public var activeProfile: Profile {
        // Construction and every mutation preserve active membership.
        profiles.first { $0.id == activeProfileID }!
    }

    /// Invalid stored collections are replaced as a whole. Valid collections
    /// retain edited built-ins and custom order, with built-ins placed first.
    public init(restoring stored: [Profile]? = nil, activeProfileID requestedID: UUID? = nil) {
        guard let stored, Self.isValid(stored) else {
            profiles = Profile.builtIns
            activeProfileID = Profile.builtIns[0].id
            return
        }
        let builtInIDs = Profile.builtIns.map(\.id)
        let ordered = builtInIDs.compactMap { id in stored.first { $0.id == id } }
            + stored.filter { !builtInIDs.contains($0.id) }
        profiles = ordered
        activeProfileID = requestedID.flatMap { id in
            ordered.contains { $0.id == id } ? id : nil
        } ?? ordered[0].id
    }

    public func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    public func validatedName(_ name: String, excluding profileID: UUID? = nil) throws -> String {
        guard let trimmed = name.nonblank else { throw ProfileMutationError.emptyName }
        let key = Self.nameKey(trimmed)
        guard !profiles.contains(where: { $0.id != profileID && Self.nameKey($0.name) == key }) else {
            throw ProfileMutationError.duplicateName
        }
        return trimmed
    }

    public mutating func select(id: UUID) throws {
        guard profile(id: id) != nil else { throw ProfileMutationError.unknownProfile }
        activeProfileID = id
    }

    public mutating func update(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileMutationError.unknownProfile
        }
        var validated = profile
        validated.name = try validatedName(profile.name, excluding: profile.id)
        profiles[index] = validated
    }

    public mutating func add(_ profile: Profile) throws {
        guard self.profile(id: profile.id) == nil else { throw ProfileMutationError.duplicateID }
        var validated = profile
        validated.name = try validatedName(profile.name)
        profiles.append(validated)
    }

    public mutating func delete(id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileMutationError.lastProfile }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileMutationError.unknownProfile
        }
        profiles.remove(at: index)
        if activeProfileID == id {
            activeProfileID = profiles[min(index, profiles.count - 1)].id
        }
    }

    private static func isValid(_ profiles: [Profile]) -> Bool {
        guard !profiles.isEmpty else { return false }
        var ids: Set<UUID> = []
        var names: Set<String> = []
        return profiles.allSatisfy { profile in
            profile.name.nonblank == profile.name
                && ids.insert(profile.id).inserted
                && names.insert(nameKey(profile.name)).inserted
        }
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
