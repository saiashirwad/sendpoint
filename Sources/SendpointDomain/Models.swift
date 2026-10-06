import Foundation

public enum Subject: Codable, Hashable, Sendable {
    case selection(quote: String)
    case standalone
}

public struct Note: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var subject: Subject
    public var body: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        subject: Subject,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.body = body
        self.createdAt = createdAt
    }
}

public enum StackSlot: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case one = 1, two, three, four, five

    public var id: Self { self }
    public var number: Int { rawValue }
}

public struct Stack: Hashable, Sendable, Identifiable {
    public let id: StackSlot
    public var notes: [Note]

    public init(id: StackSlot = .one, notes: [Note] = []) {
        self.id = id
        self.notes = notes
    }

    public var startedAt: Date? {
        notes.map(\.createdAt).min()
    }
}

public struct ClearedBatch: Codable, Hashable, Sendable {
    public let stackID: StackSlot
    public var notes: [Note]

    public init(stackID: StackSlot, notes: [Note]) {
        self.stackID = stackID
        self.notes = notes
    }
}

public struct StackDocument: Codable, Hashable, Sendable {
    public static let stackCount = StackSlot.allCases.count

    private var one: [Note] = []
    private var two: [Note] = []
    private var three: [Note] = []
    private var four: [Note] = []
    private var five: [Note] = []
    public internal(set) var lastCleared: ClearedBatch?

    public init() {}

    public var stacks: [Stack] {
        StackSlot.allCases.map { Stack(id: $0, notes: self[$0]) }
    }

    public internal(set) subscript(slot: StackSlot) -> [Note] {
        get {
            switch slot {
            case .one: one
            case .two: two
            case .three: three
            case .four: four
            case .five: five
            }
        }
        set {
            switch slot {
            case .one: one = newValue
            case .two: two = newValue
            case .three: three = newValue
            case .four: four = newValue
            case .five: five = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case one, two, three, four, five, lastCleared }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        one = try values.decode([Note].self, forKey: .one)
        two = try values.decode([Note].self, forKey: .two)
        three = try values.decode([Note].self, forKey: .three)
        four = try values.decode([Note].self, forKey: .four)
        five = try values.decode([Note].self, forKey: .five)
        lastCleared = try values.decodeIfPresent(ClearedBatch.self, forKey: .lastCleared)
        for slot in StackSlot.allCases {
            let notes = self[slot]
            guard Set(notes.map(\.id)).count == notes.count else {
                throw DecodingError.dataCorruptedError(forKey: .one, in: values,
                    debugDescription: "Note IDs must be unique within a stack.")
            }
        }
        if let batch = lastCleared {
            guard !batch.notes.isEmpty, Set(batch.notes.map(\.id)).count == batch.notes.count else {
                throw DecodingError.dataCorruptedError(forKey: .lastCleared, in: values,
                    debugDescription: "The cleared batch must contain unique notes.")
            }
        }
    }
}

public extension Array where Element == Stack {
    func stack(id: StackSlot) -> Stack? {
        first { $0.id == id }
    }

    func stack(number: Int) -> Stack? {
        StackSlot(rawValue: number).flatMap { stack(id: $0) }
    }
}
