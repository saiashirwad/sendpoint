import Foundation

public enum StackDocumentMigration {
    public static let legacyVersion = 3

    private struct LegacyStack: Decodable {
        var id: UUID
        var notes: [Note]
    }

    private struct LegacyDocument: Decodable {
        var stacks: [LegacyStack]
        var currentStackID: UUID
        var lastCleared: ClearedBatch?
        var recentStackIDs: [UUID]?
    }

    public static func migrate(legacy data: Data, decoder: JSONDecoder) throws -> StackDocument {
        let legacy = try decoder.decode(LegacyDocument.self, from: data)
        var seen = Set<UUID>()
        var ordered: [LegacyStack] = []
        let preferred = [legacy.currentStackID] + (legacy.recentStackIDs ?? []) + legacy.stacks.map(\.id)
        for id in preferred where seen.insert(id).inserted {
            if let stack = legacy.stacks.first(where: { $0.id == id }) { ordered.append(stack) }
        }

        var stacks = ordered.prefix(StackDocument.stackCount).map { Stack(id: $0.id, notes: $0.notes) }
        while stacks.count < StackDocument.stackCount { stacks.append(Stack()) }

        let kept = Set(stacks.map(\.id))
        let document = StackDocument(
            stacks: stacks,
            currentStackID: kept.contains(legacy.currentStackID) ? legacy.currentStackID : stacks[0].id,
            lastCleared: legacy.lastCleared.flatMap { kept.contains($0.stackID) ? $0 : nil }
        )
        try StackDocumentMutations.validate(document)
        return document
    }
}
