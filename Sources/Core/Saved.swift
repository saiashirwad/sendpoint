import Foundation

/// The persisted slice of World. Mode and take are session-only.
public struct Saved: Codable, Equatable {
    public var stacks: [[Note]]
    public var active: Int

    public init(_ w: World) {
        stacks = w.stacks
        active = w.active
    }

    public var world: World {
        var padded = Array(stacks.prefix(stackCount))
        padded += Array(repeating: [], count: stackCount - padded.count)
        return World(stacks: padded, active: padded.indices.contains(active) ? active : 0)
    }

    public static func decode(_ data: Data) -> World? {
        (try? JSONDecoder().decode(Saved.self, from: data))?.world
    }

    public static func encode(_ w: World) -> Data {
        (try? JSONEncoder().encode(Saved(w))) ?? Data()
    }
}
